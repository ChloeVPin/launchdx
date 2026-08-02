import Foundation

public final class MachOInspector {
    private let maxArchitectureCount = 128
    private let maxLoadCommandCount = 4096

    public init() {}

    public func inspect(path: String) -> MachOInspection {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
            return inspect(data: data, path: path)
        } catch {
            return MachOInspection(
                path: path,
                format: .unknown,
                isReadable: false,
                isMachO: false,
                isMalformed: false,
                architectures: [],
                supportsArm64: false,
                supportsX86_64: false,
                minimumOSVersion: nil,
                sdkVersion: nil,
                hasCodeSignatureLoadCommand: false,
                codeSignatureRangeValid: false,
                slices: [],
                error: "The executable could not be read: \(error.localizedDescription)"
            )
        }
    }

    public func inspect(data: Data, path: String = "<memory>") -> MachOInspection {
        guard data.count >= 4 else {
            return malformed(path: path, detail: "The file is shorter than a Mach-O magic value.")
        }

        let littleMagic = readUInt32(data, at: 0, endian: .little)
        let bigMagic = readUInt32(data, at: 0, endian: .big)

        if littleMagic == MachOMagic.thin32 || littleMagic == MachOMagic.thin64 {
            return inspectThin(data: data, path: path, endian: .little, is64Bit: littleMagic == MachOMagic.thin64)
        }
        if bigMagic == MachOMagic.thin32 || bigMagic == MachOMagic.thin64 {
            return inspectThin(data: data, path: path, endian: .big, is64Bit: bigMagic == MachOMagic.thin64)
        }
        if bigMagic == MachOMagic.fat32 || bigMagic == MachOMagic.fat64 {
            return inspectFat(data: data, path: path, endian: .big, is64Bit: bigMagic == MachOMagic.fat64)
        }
        if littleMagic == MachOMagic.fat32 || littleMagic == MachOMagic.fat64 {
            return inspectFat(data: data, path: path, endian: .little, is64Bit: littleMagic == MachOMagic.fat64)
        }

        return MachOInspection(
            path: path,
            format: .unknown,
            isMachO: false,
            isMalformed: false,
            architectures: [],
            supportsArm64: false,
            supportsX86_64: false,
            minimumOSVersion: nil,
            sdkVersion: nil,
            hasCodeSignatureLoadCommand: false,
            codeSignatureRangeValid: false,
            slices: [],
            error: "The file does not begin with a recognized Mach-O or universal-binary magic value."
        )
    }

    private func inspectFat(data: Data, path: String, endian: ByteOrder, is64Bit: Bool) -> MachOInspection {
        let entrySize = is64Bit ? 32 : 20
        guard let count = readUInt32(data, at: 4, endian: endian),
              count > 0,
              count <= UInt32(maxArchitectureCount) else {
            return malformed(path: path, detail: "The universal-binary architecture count is invalid, empty, or exceeds the safety limit.")
        }
        let tableSize = Int(count) * entrySize
        guard checkedRange(offset: 8, length: tableSize, in: data) else {
            return malformed(path: path, detail: "The universal-binary architecture table is truncated.")
        }

        var slices: [MachOSliceInspection] = []
        var malformedSlice = false
        for index in 0..<Int(count) {
            let entryOffset = 8 + index * entrySize
            guard let cpuType = readUInt32(data, at: entryOffset, endian: endian) else {
                return malformed(path: path, detail: "The universal-binary architecture entry is truncated.")
            }
            let offset: UInt64
            let size: UInt64
            if is64Bit {
                guard let parsedOffset = readUInt64(data, at: entryOffset + 8, endian: endian),
                      let parsedSize = readUInt64(data, at: entryOffset + 16, endian: endian) else {
                    return malformed(path: path, detail: "The 64-bit universal-binary architecture entry is truncated.")
                }
                offset = parsedOffset
                size = parsedSize
            } else {
                guard let parsedOffset = readUInt32(data, at: entryOffset + 8, endian: endian),
                      let parsedSize = readUInt32(data, at: entryOffset + 12, endian: endian) else {
                    return malformed(path: path, detail: "The universal-binary architecture entry is truncated.")
                }
                offset = UInt64(parsedOffset)
                size = UInt64(parsedSize)
            }

            guard offset <= UInt64(data.count), size <= UInt64(data.count) - offset,
                  offset <= UInt64(Int.max), size <= UInt64(Int.max) else {
                return malformed(path: path, detail: "A universal-binary slice points outside the file.")
            }

            let sliceData = data.subdata(in: Int(offset)..<Int(offset + size))
            let slicePath = "\(path)[slice \(index)]"
            let sliceInspection = inspectThinOrMalformed(
                data: sliceData,
                path: slicePath,
                expectedCPUType: cpuType
            )
            malformedSlice = malformedSlice || sliceInspection.isMalformed
            slices.append(sliceInspection)
        }

        let architectures = unique(slices.map(\.architecture).filter { $0 != "unknown" })
        let hasCodeSignature = slices.contains { $0.hasCodeSignatureLoadCommand }
        let codeSignatureValid = slices.allSatisfy { !$0.hasCodeSignatureLoadCommand || $0.codeSignatureRangeValid }
        return MachOInspection(
            path: path,
            format: .universal,
            isMachO: true,
            isMalformed: malformedSlice,
            architectures: architectures,
            supportsArm64: slices.contains { $0.architecture == "arm64" },
            supportsX86_64: slices.contains { $0.architecture == "x86_64" },
            minimumOSVersion: firstNonNil(slices.compactMap(\.minimumOSVersion)),
            sdkVersion: firstNonNil(slices.compactMap(\.sdkVersion)),
            hasCodeSignatureLoadCommand: hasCodeSignature,
            codeSignatureRangeValid: codeSignatureValid,
            slices: slices,
            error: malformedSlice ? "One or more universal-binary slices are malformed." : nil
        )
    }

    private func inspectThinOrMalformed(data: Data, path: String, expectedCPUType: UInt32) -> MachOSliceInspection {
        guard data.count >= 4 else {
            return malformedSlice(path: path, cpuType: expectedCPUType, detail: "The Mach-O slice is shorter than its magic value.")
        }
        let littleMagic = readUInt32(data, at: 0, endian: .little)
        let bigMagic = readUInt32(data, at: 0, endian: .big)
        if littleMagic == MachOMagic.thin32 || littleMagic == MachOMagic.thin64 {
            return inspectSlice(data: data, path: path, endian: .little, is64Bit: littleMagic == MachOMagic.thin64, expectedCPUType: expectedCPUType)
        }
        if bigMagic == MachOMagic.thin32 || bigMagic == MachOMagic.thin64 {
            return inspectSlice(data: data, path: path, endian: .big, is64Bit: bigMagic == MachOMagic.thin64, expectedCPUType: expectedCPUType)
        }
        return malformedSlice(path: path, cpuType: expectedCPUType, detail: "The universal-binary slice does not contain a recognized Mach-O header.")
    }

    private func inspectThin(data: Data, path: String, endian: ByteOrder, is64Bit: Bool) -> MachOInspection {
        let slice = inspectSlice(data: data, path: path, endian: endian, is64Bit: is64Bit, expectedCPUType: nil)
        let architecture = slice.architecture == "unknown" ? [] : [slice.architecture]
        return MachOInspection(
            path: path,
            format: .thin,
            isMachO: true,
            isMalformed: slice.isMalformed,
            architectures: architecture,
            supportsArm64: slice.architecture == "arm64",
            supportsX86_64: slice.architecture == "x86_64",
            minimumOSVersion: slice.minimumOSVersion,
            sdkVersion: slice.sdkVersion,
            hasCodeSignatureLoadCommand: slice.hasCodeSignatureLoadCommand,
            codeSignatureRangeValid: slice.codeSignatureRangeValid,
            slices: [slice],
            error: slice.error
        )
    }

    private func inspectSlice(
        data: Data,
        path: String,
        endian: ByteOrder,
        is64Bit: Bool,
        expectedCPUType: UInt32?
    ) -> MachOSliceInspection {
        let headerSize = is64Bit ? 32 : 28
        guard data.count >= headerSize,
              let cpuType = readUInt32(data, at: 4, endian: endian),
              let ncmds = readUInt32(data, at: 16, endian: endian),
              let sizeofcmds = readUInt32(data, at: 20, endian: endian) else {
            return malformedSlice(path: path, cpuType: expectedCPUType ?? 0, detail: "The Mach-O header is truncated.")
        }
        guard ncmds <= UInt32(maxLoadCommandCount),
              UInt64(ncmds) <= UInt64(data.count / 8),
              UInt64(sizeofcmds) <= UInt64(data.count - headerSize),
              checkedRange(offset: headerSize, length: Int(sizeofcmds), in: data) else {
            return malformedSlice(path: path, cpuType: cpuType, detail: "The Mach-O load-command region is outside the file.")
        }
        if let expectedCPUType, expectedCPUType != cpuType {
            return malformedSlice(path: path, cpuType: cpuType, detail: "The slice CPU type does not match its universal-binary table entry.")
        }

        var minimumOSVersion: String?
        var sdkVersion: String?
        var hasCodeSignature = false
        var codeSignatureRangeValid = true
        var commandOffset = headerSize
        let commandEnd = headerSize + Int(sizeofcmds)

        for _ in 0..<Int(ncmds) {
            guard commandOffset <= commandEnd,
                  let command = readUInt32(data, at: commandOffset, endian: endian),
                  let commandSize = readUInt32(data, at: commandOffset + 4, endian: endian),
                  commandSize >= 8,
                  Int(commandSize) <= commandEnd - commandOffset else {
                return malformedSlice(path: path, cpuType: cpuType, detail: "A Mach-O load command has an invalid size.")
            }

            let size = Int(commandSize)
            if command == MachOLoadCommand.buildVersion && size >= 24 {
                minimumOSVersion = versionString(readUInt32(data, at: commandOffset + 12, endian: endian))
                sdkVersion = versionString(readUInt32(data, at: commandOffset + 16, endian: endian))
            } else if command == MachOLoadCommand.versionMinMacOS && size >= 16 {
                minimumOSVersion = versionString(readUInt32(data, at: commandOffset + 8, endian: endian))
                sdkVersion = versionString(readUInt32(data, at: commandOffset + 12, endian: endian))
            } else if command == MachOLoadCommand.codeSignature && size >= 16 {
                hasCodeSignature = true
                if let dataOffset = readUInt32(data, at: commandOffset + 8, endian: endian),
                   let dataSize = readUInt32(data, at: commandOffset + 12, endian: endian),
                   Int(dataOffset) >= 0,
                   Int(dataSize) >= 0,
                   checkedRange(offset: Int(dataOffset), length: Int(dataSize), in: data) {
                    codeSignatureRangeValid = true
                } else {
                    codeSignatureRangeValid = false
                }
            }
            commandOffset += size
        }

        guard commandOffset == commandEnd else {
            return malformedSlice(path: path, cpuType: cpuType, detail: "The Mach-O load-command sizes do not match sizeofcmds.")
        }

        return MachOSliceInspection(
            architecture: architectureName(cpuType: cpuType, is64Bit: is64Bit),
            cpuType: cpuType,
            is64Bit: is64Bit,
            minimumOSVersion: minimumOSVersion,
            sdkVersion: sdkVersion,
            hasCodeSignatureLoadCommand: hasCodeSignature,
            codeSignatureRangeValid: codeSignatureRangeValid,
            isMalformed: !codeSignatureRangeValid,
            error: codeSignatureRangeValid ? nil : "The LC_CODE_SIGNATURE data range is outside the file."
        )
    }

    private func malformed(path: String, detail: String) -> MachOInspection {
        MachOInspection(
            path: path,
            format: .unknown,
            isMachO: false,
            isMalformed: true,
            architectures: [],
            supportsArm64: false,
            supportsX86_64: false,
            minimumOSVersion: nil,
            sdkVersion: nil,
            hasCodeSignatureLoadCommand: false,
            codeSignatureRangeValid: false,
            slices: [],
            error: detail
        )
    }

    private func malformedSlice(path: String, cpuType: UInt32, detail: String) -> MachOSliceInspection {
        MachOSliceInspection(
            architecture: "unknown",
            cpuType: cpuType,
            is64Bit: nil,
            minimumOSVersion: nil,
            sdkVersion: nil,
            hasCodeSignatureLoadCommand: false,
            codeSignatureRangeValid: false,
            isMalformed: true,
            error: detail
        )
    }

    private func checkedRange(offset: Int, length: Int, in data: Data) -> Bool {
        offset >= 0 && length >= 0 && offset <= data.count && length <= data.count - offset
    }

    private func readUInt32(_ data: Data, at offset: Int, endian: ByteOrder) -> UInt32? {
        guard checkedRange(offset: offset, length: 4, in: data) else { return nil }
        let bytes = data[offset..<(offset + 4)]
        var value: UInt32 = 0
        switch endian {
        case .little:
            for (index, byte) in bytes.enumerated() {
                value |= UInt32(byte) << UInt32(index * 8)
            }
        case .big:
            for byte in bytes {
                value = (value << 8) | UInt32(byte)
            }
        }
        return value
    }

    private func readUInt64(_ data: Data, at offset: Int, endian: ByteOrder) -> UInt64? {
        guard checkedRange(offset: offset, length: 8, in: data) else { return nil }
        let bytes = data[offset..<(offset + 8)]
        var value: UInt64 = 0
        switch endian {
        case .little:
            for (index, byte) in bytes.enumerated() {
                value |= UInt64(byte) << UInt64(index * 8)
            }
        case .big:
            for byte in bytes {
                value = (value << 8) | UInt64(byte)
            }
        }
        return value
    }

    private func architectureName(cpuType: UInt32, is64Bit: Bool) -> String {
        switch cpuType {
        case MachOCPU.arm:
            return is64Bit ? "arm64" : "arm"
        case MachOCPU.x86:
            return is64Bit ? "x86_64" : "i386"
        case MachOCPU.arm64:
            return "arm64"
        case MachOCPU.x86_64:
            return "x86_64"
        default:
            return "unknown(0x\(String(cpuType, radix: 16)))"
        }
    }

    private func versionString(_ value: UInt32?) -> String? {
        guard let value else { return nil }
        let major = (value >> 16) & 0xffff
        let minor = (value >> 8) & 0xff
        let patch = value & 0xff
        return "\(major).\(minor).\(patch)"
    }

    private func unique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !result.contains(value) {
            result.append(value)
        }
        return result
    }

    private func firstNonNil(_ values: [String]) -> String? {
        values.first
    }
}

private enum ByteOrder {
    case little
    case big
}

private enum MachOMagic {
    static let thin32: UInt32 = 0xfeedface
    static let thin64: UInt32 = 0xfeedfacf
    static let fat32: UInt32 = 0xcafebabe
    static let fat64: UInt32 = 0xcafebabf
}

private enum MachOLoadCommand {
    static let versionMinMacOS: UInt32 = 0x24
    static let codeSignature: UInt32 = 0x1d
    static let buildVersion: UInt32 = 0x32
}

private enum MachOCPU {
    static let arm: UInt32 = 12
    static let x86: UInt32 = 7
    static let arm64: UInt32 = 0x0100000c
    static let x86_64: UInt32 = 0x01000007
}

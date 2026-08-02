import Foundation
import XCTest
@testable import LaunchDXCore

final class MachOInspectorTests: XCTestCase {
    private let inspector = MachOInspector()

    func testThinArm64MachOPasses() {
        let result = inspector.inspect(data: thinMachO(cpuType: 0x0100000c), path: "arm64")

        XCTAssertEqual(result.format, .thin)
        XCTAssertTrue(result.isMachO)
        XCTAssertFalse(result.isMalformed)
        XCTAssertEqual(result.architectures, ["arm64"])
        XCTAssertTrue(result.supportsArm64)
        XCTAssertFalse(result.supportsX86_64)
        XCTAssertEqual(result.slices.count, 1)
    }

    func testThinX86OnlyMachOIsReported() {
        let result = inspector.inspect(data: thinMachO(cpuType: 0x01000007), path: "x86_64")

        XCTAssertEqual(result.format, .thin)
        XCTAssertEqual(result.architectures, ["x86_64"])
        XCTAssertFalse(result.supportsArm64)
        XCTAssertTrue(result.supportsX86_64)
    }

    func testUniversalMachOReportsBothArchitectures() {
        let arm = thinMachO(cpuType: 0x0100000c)
        let x86 = thinMachO(cpuType: 0x01000007)
        let result = inspector.inspect(data: universalMachO(slices: [arm, x86]), path: "universal")

        XCTAssertEqual(result.format, .universal)
        XCTAssertTrue(result.isMachO)
        XCTAssertFalse(result.isMalformed)
        XCTAssertEqual(result.architectures, ["arm64", "x86_64"])
        XCTAssertTrue(result.supportsArm64)
        XCTAssertTrue(result.supportsX86_64)
        XCTAssertEqual(result.slices.count, 2)
    }

    func testTruncatedMachOIsMalformedWithoutCrashing() {
        let result = inspector.inspect(data: Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c]), path: "truncated")

        XCTAssertTrue(result.isMachO)
        XCTAssertTrue(result.isMalformed)
        XCTAssertNotNil(result.error)
    }

    func testNonMachOIsNotReportedAsMalformedMachO() {
        let result = inspector.inspect(data: Data("not Mach-O".utf8), path: "text")

        XCTAssertTrue(result.isReadable)
        XCTAssertFalse(result.isMachO)
        XCTAssertFalse(result.isMalformed)
        XCTAssertEqual(result.format, .unknown)
    }

    func testBuildVersionAndCodeSignatureAreBoundedAndDecoded() {
        let data = thinMachO(
            cpuType: 0x0100000c,
            commands: concatenate(
                loadCommand(
                    command: 0x32,
                    payload: concatenate(uint32(0), uint32(13 << 16 | 2 << 8 | 1), uint32(14 << 16 | 3 << 8 | 0), uint32(0))
                ),
                loadCommand(
                    command: 0x1d,
                    payload: concatenate(uint32(72), uint32(4))
                )
            ),
            extraData: Data([0xde, 0xad, 0xbe, 0xef])
        )
        let result = inspector.inspect(data: data, path: "commands")

        XCTAssertFalse(result.isMalformed)
        XCTAssertEqual(result.minimumOSVersion, "13.2.1")
        XCTAssertEqual(result.sdkVersion, "14.3.0")
        XCTAssertTrue(result.hasCodeSignatureLoadCommand)
        XCTAssertTrue(result.codeSignatureRangeValid)
    }

    func testUnreadablePathIsUnavailable() {
        let result = inspector.inspect(path: "/definitely/missing/launchdx-executable")

        XCTAssertFalse(result.isReadable)
        XCTAssertFalse(result.isMachO)
        XCTAssertFalse(result.isMalformed)
        XCTAssertNotNil(result.error)
    }

    func testZeroEntryUniversalBinaryIsMalformed() {
        let data = concatenate(uint32BE(0xcafebabe), uint32BE(0))
        let result = inspector.inspect(data: data, path: "empty-universal")

        XCTAssertFalse(result.isMachO)
        XCTAssertTrue(result.isMalformed)
        XCTAssertEqual(result.format, .unknown)
    }

    func testOutOfBoundsCodeSignatureIsMalformed() {
        let data = thinMachO(
            cpuType: 0x0100000c,
            commands: loadCommand(command: 0x1d, payload: concatenate(uint32(4096), uint32(4)))
        )
        let result = inspector.inspect(data: data, path: "bad-signature-range")

        XCTAssertTrue(result.isMachO)
        XCTAssertTrue(result.isMalformed)
        XCTAssertTrue(result.hasCodeSignatureLoadCommand)
        XCTAssertFalse(result.codeSignatureRangeValid)
    }

    private func thinMachO(cpuType: UInt32, commands: Data = Data(), extraData: Data = Data()) -> Data {
        var data = Data()
        data.append(contentsOf: uint32(0xfeedfacf))
        data.append(contentsOf: uint32(cpuType))
        data.append(contentsOf: uint32(0))
        data.append(contentsOf: uint32(2))
        data.append(contentsOf: uint32(UInt32(commands.isEmpty ? 0 : commandCount(in: commands))))
        data.append(contentsOf: uint32(UInt32(commands.count)))
        data.append(contentsOf: uint32(0))
        data.append(contentsOf: uint32(0))
        data.append(commands)
        data.append(extraData)
        return data
    }

    private func universalMachO(slices: [Data]) -> Data {
        let headerSize = 8 + slices.count * 20
        var offsets: [Int] = []
        var nextOffset = headerSize
        for slice in slices {
            offsets.append(nextOffset)
            nextOffset += slice.count
        }

        var data = Data()
        data.append(contentsOf: uint32BE(0xcafebabe))
        data.append(contentsOf: uint32BE(UInt32(slices.count)))
        for (index, slice) in slices.enumerated() {
            let cpuType: UInt32 = index == 0 ? 0x0100000c : 0x01000007
            data.append(contentsOf: uint32BE(cpuType))
            data.append(contentsOf: uint32BE(0))
            data.append(contentsOf: uint32BE(UInt32(offsets[index])))
            data.append(contentsOf: uint32BE(UInt32(slice.count)))
            data.append(contentsOf: uint32BE(2))
        }
        for slice in slices {
            data.append(slice)
        }
        return data
    }

    private func loadCommand(command: UInt32, payload: Data) -> Data {
        var data = uint32(command)
        data.append(contentsOf: uint32(UInt32(8 + payload.count)))
        data.append(payload)
        return data
    }

    private func concatenate(_ values: Data...) -> Data {
        var result = Data()
        values.forEach { result.append($0) }
        return result
    }

    private func commandCount(in commands: Data) -> Int {
        var offset = 0
        var count = 0
        while offset + 8 <= commands.count {
            let size = Int(commands[offset + 4])
            guard size > 0 else { return count }
            offset += size
            count += 1
        }
        return count
    }

    private func uint32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ])
    }

    private func uint32BE(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
}

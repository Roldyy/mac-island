import Testing
@testable import FanShared

@Suite struct SMCKeyTests {
    @Test func encodesFourASCIICharsBigEndian() {
        #expect(SMCKey("F0Ac")?.code == 0x4630_4163)
        #expect(SMCKey("FNum")?.description == "FNum")
        #expect(SMCDataType("flt ")?.description == "flt ")
    }

    @Test func refusesWrongLengthOrNonASCII() {
        #expect(SMCKey("F0A") == nil)
        #expect(SMCKey("F0Acc") == nil)
        #expect(SMCKey("F0Aé") == nil)
        #expect(SMCKey("F0A\u{0}") == nil)
    }

    @Test func onlyModeTargetAndUnlockKeysAreWritable() {
        for name in ["Ftst", "F0Md", "F1Md", "F9Md", "F0Tg", "F1Tg", "F9Tg"] {
            #expect(FanSMCKeys.isWritable(SMCKey(name)!), "\(name)")
        }
        for name in ["F0Mn", "F0Mx", "F0Ac", "FNum", "FS! ", "F0Sf", "Tp01", "#KEY", "MSAL", "FMdx", "FaMd", "F0md"] {
            #expect(!FanSMCKeys.isWritable(SMCKey(name)!), "\(name)")
        }
    }

    @Test func fanKeysCoverOnlySingleDigitIndexes() {
        #expect(FanSMCKeys.actual(0)?.description == "F0Ac")
        #expect(FanSMCKeys.minimum(1)?.description == "F1Mn")
        #expect(FanSMCKeys.maximum(9)?.description == "F9Mx")
        #expect(FanSMCKeys.target(0)?.description == "F0Tg")
        #expect(FanSMCKeys.mode(0)?.description == "F0Md")
        #expect(FanSMCKeys.actual(10) == nil)
        #expect(FanSMCKeys.actual(-1) == nil)
    }
}

@Suite struct SMCCodecTests {
    @Test func decodesLittleEndianFloat() {
        let bytes = withUnsafeBytes(of: Float(2317.5).bitPattern.littleEndian) { Array($0) }
        #expect(SMCCodec.decode(bytes, type: .flt) == 2317.5)
    }

    @Test func decodesBigEndianIntegersAndFixedPoint() {
        #expect(SMCCodec.decode([2], type: .ui8) == 2)
        #expect(SMCCodec.decode([0x01, 0x02], type: .ui16) == 258)
        #expect(SMCCodec.decode([0, 0, 0x01, 0x00], type: .ui32) == 256)
        #expect(SMCCodec.decode([0x24, 0x34], type: .fpe2) == 2317)      // 0x2434 / 4
        #expect(SMCCodec.decode([0x2A, 0x80], type: .sp78) == 42.5)
        #expect(SMCCodec.decode([0xF6, 0x00], type: .sp78) == -10)
    }

    @Test func refusesShortBuffersNonFiniteAndUnknownTypes() {
        #expect(SMCCodec.decode([1, 2], type: .flt) == nil)
        #expect(SMCCodec.decode([], type: .ui8) == nil)
        let nan = withUnsafeBytes(of: Float.nan.bitPattern.littleEndian) { Array($0) }
        #expect(SMCCodec.decode(nan, type: .flt) == nil)
        #expect(SMCCodec.decode([1, 2, 3, 4], type: SMCDataType("ch8*")!) == nil)
    }

    @Test func encodesOnlyWellFormedValuesForTheKeyType() {
        let flt = SMCKeyInfo(size: 4, type: .flt, attributes: 0)
        #expect(SMCCodec.encode(3000, as: flt) == withUnsafeBytes(of: Float(3000).bitPattern.littleEndian) { Array($0) })
        let ui8 = SMCKeyInfo(size: 1, type: .ui8, attributes: 0)
        #expect(SMCCodec.encode(1, as: ui8) == [1])
        #expect(SMCCodec.encode(256, as: ui8) == nil)
        #expect(SMCCodec.encode(-1, as: ui8) == nil)
        #expect(SMCCodec.encode(0.5, as: ui8) == nil)
        #expect(SMCCodec.encode(.nan, as: flt) == nil)
        #expect(SMCCodec.encode(.infinity, as: flt) == nil)
        let fpe2 = SMCKeyInfo(size: 2, type: .fpe2, attributes: 0)
        #expect(SMCCodec.encode(2317, as: fpe2) == [0x24, 0x34])
        // Size disagreeing with the type is refused, never truncated.
        #expect(SMCCodec.encode(3000, as: SMCKeyInfo(size: 2, type: .flt, attributes: 0)) == nil)
        #expect(SMCCodec.encode(1, as: SMCKeyInfo(size: 4, type: SMCDataType("ch8*")!, attributes: 0)) == nil)
    }
}

@Suite struct SMCParamStructTests {
    @Test func layoutMatchesTheEightyByteCStruct() {
        var p = SMCParamStruct()
        p.key = SMCKey("F0Ac")!.code
        p.dataSize = 4
        p.dataType = SMCDataType.flt.code
        p.dataAttributes = 0xD4
        p.result = 0x84
        p.status = 7
        p.data8 = 9
        p.data32 = 0x0102_0304
        p.bytes[0] = 0xAA
        p.bytes[31] = 0xBB
        let raw = p.encoded()
        #expect(raw.count == 80)
        #expect(Array(raw[0..<4]) == withUnsafeBytes(of: SMCKey("F0Ac")!.code) { Array($0) })
        #expect(Array(raw[28..<32]) == withUnsafeBytes(of: UInt32(4)) { Array($0) })
        #expect(Array(raw[32..<36]) == withUnsafeBytes(of: SMCDataType.flt.code) { Array($0) })
        #expect(raw[36] == 0xD4)
        #expect(raw[40] == 0x84)
        #expect(raw[41] == 7)
        #expect(raw[42] == 9)
        #expect(Array(raw[44..<48]) == withUnsafeBytes(of: UInt32(0x0102_0304)) { Array($0) })
        #expect(raw[48] == 0xAA)
        #expect(raw[79] == 0xBB)
        #expect(SMCParamStruct(decoding: raw) == p)
    }

    @Test func decodingAShortBufferGivesNil() {
        #expect(SMCParamStruct(decoding: [UInt8](repeating: 0, count: 79)) == nil)
    }

    @Test func readOnlyClientHasNoWriteCommand() {
        // 6 is the SMC write-bytes command. The read-only type must not be able to express it.
        let commands = AppleSMCReadOnlyClient.ReadCommand.allCases.map(\.rawValue)
        #expect(Set(commands) == [5, 8, 9])
        #expect(!commands.contains(6))
    }
}

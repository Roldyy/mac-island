import Foundation
import Testing
@testable import CommandBarFeature

@Suite struct CalculatorTests {
    private func value(_ s: String) -> Double? {
        if case .success(let v) = Calculator.evaluate(s) { return v }
        return nil
    }

    @Test(arguments: [
        ("1+2", 3.0), ("2*3+4", 10.0), ("2+3*4", 14.0), ("(2+3)*4", 20.0), ("10/4", 2.5),
        ("2^10", 1024.0), ("2^3^2", 512.0), ("-2^2", -4.0), ("2^-1", 0.5), ("--3", 3.0),
        ("50%", 0.5), ("200+10%", 220.0), ("200-10%", 180.0), ("200*10%", 20.0),
        ("3,5*2", 7.0), ("1.5+1.5", 3.0), ("6\u{00D7}7", 42.0), ("8\u{00F7}2", 4.0),
        (" ( 1 + 2 ) * ( 3 - 1 ) ", 6.0), ("((((1))))", 1.0),
    ])
    func evaluates(_ input: String, _ expected: Double) {
        let v = value(input)
        #expect(v != nil)
        if let v { #expect(abs(v - expected) < 1e-9, "\(input)") }
    }

    @Test func divisionByZero() {
        #expect(Calculator.evaluate("1/0") == .failure(.divisionByZero))
        #expect(Calculator.evaluate("5/(2-2)") == .failure(.divisionByZero))
    }

    @Test(arguments: ["", "   ", "+", "1+", "*2", "(1+2", "1+2)", "()", "1 2", "1..2", "abc", "2**3",
                      "1+a", "sin(1)", "$(whoami)", "1;2", "`ls`", "1,,2", "%", "1%%%x"])
    func malformedIsAnErrorNotACrash(_ input: String) {
        if case .success = Calculator.evaluate(input) { Issue.record("accepted \(input)") }
    }

    @Test func overflowIsNotFinite() {
        #expect(Calculator.evaluate("9^9^9") == .failure(.notFinite))
    }

    @Test func absurdNestingIsRefusedNotCrashed() {
        let deep = String(repeating: "(", count: 5000) + "1" + String(repeating: ")", count: 5000)
        #expect(Calculator.evaluate(deep) == .failure(.tooComplex))
        #expect(Calculator.evaluate(String(repeating: "1+", count: 500) + "1") == .failure(.tooComplex))
    }

    @Test func formatting() {
        let en = Locale(identifier: "en_US")
        let fr = Locale(identifier: "fr_BE")
        #expect(Calculator.format(0.1 + 0.2, locale: en) == "0.3")
        #expect(Calculator.format(1024, locale: en) == "1024")
        #expect(Calculator.format(2.5, locale: fr) == "2,5")
        #expect(Calculator.format(1_000_000, locale: en) == "1000000")
    }

    @Test func looksLikeExpression() {
        #expect(Calculator.looksLikeExpression("2+2"))
        #expect(Calculator.looksLikeExpression("(3)"))
        #expect(!Calculator.looksLikeExpression("42"))        // a bare number is not a calculation
        #expect(!Calculator.looksLikeExpression("safari"))
        #expect(!Calculator.looksLikeExpression("a-b"))       // no digit
    }
}

import Foundation

enum CalculatorError: Error, Equatable {
    case empty, syntax, divisionByZero, notFinite, tooComplex
}

/// Hand-written recursive-descent evaluator: `+ - * / ^`, parentheses, postfix `%`.
/// No NSExpression, no eval: the only thing the query text can ever do is be parsed here.
///
///     expr    := term (('+' | '-') term)*          a + b% means a + a*b/100
///     term    := unary (('*' | '/') unary)*
///     unary   := ('-' | '+') unary | power
///     power   := postfix ('^' unary)?              right associative, -2^2 = -4
///     postfix := primary '%'*
///     primary := number | '(' expr ')'
enum Calculator {
    static let maxLength = 200
    static let maxDepth = 64
    static let maxTokens = 400

    static func evaluate(_ input: String) -> Result<Double, CalculatorError> {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maxLength else { return .failure(.tooComplex) }
        // Nesting is checked up front, so the parser's recursion can never get deep.
        var depth = 0, deepest = 0
        for ch in trimmed {
            if ch == "(" { depth += 1; deepest = max(deepest, depth) } else if ch == ")" { depth -= 1 }
        }
        guard deepest <= maxDepth else { return .failure(.tooComplex) }
        var parser = Parser(Array(trimmed))
        do {
            let v = try parser.parseAll()
            guard v.isFinite else { return .failure(.notFinite) }
            return .success(v)
        } catch let e as CalculatorError {
            return .failure(e)
        } catch {
            return .failure(.syntax)
        }
    }

    /// Cheap pre-filter so ordinary typing ("safari", "42") never shows a calculator row.
    static func looksLikeExpression(_ s: String) -> Bool {
        let hasDigit = s.contains { $0.isASCII && $0.isNumber }
        let hasOperator = s.contains { "+-*/^%()\u{00D7}\u{00F7}".contains($0) }
        return hasDigit && hasOperator
    }

    /// Up to 10 fraction digits, no grouping, so 0.1 + 0.2 shows as 0.3.
    static func format(_ value: Double, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        f.maximumSignificantDigits = 15
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    private struct Parser {
        let chars: [Character]
        var pos = 0
        var tokens = 0

        init(_ chars: [Character]) { self.chars = chars }

        mutating func parseAll() throws -> Double {
            let v = try expr().value
            skipSpaces()
            guard pos == chars.count else { throw CalculatorError.syntax }
            return v
        }

        private mutating func skipSpaces() { while pos < chars.count, chars[pos] == " " { pos += 1 } }

        private mutating func peek() -> Character? { skipSpaces(); return pos < chars.count ? chars[pos] : nil }

        private mutating func take() throws {
            tokens += 1
            guard tokens <= Calculator.maxTokens else { throw CalculatorError.tooComplex }
            pos += 1
        }

        // (value, wasPercentLiteral)
        private mutating func expr() throws -> (value: Double, percent: Bool) {
            var left = try term()
            while let c = peek(), c == "+" || c == "-" {
                try take()
                let right = try term()
                let r = right.percent ? left.value * right.value : right.value
                left = (c == "+" ? left.value + r : left.value - r, false)
            }
            return left
        }

        private mutating func term() throws -> (value: Double, percent: Bool) {
            var left = try unary()
            while let c = peek(), "*/\u{00D7}\u{00F7}".contains(c) {
                try take()
                let right = try unary()
                if c == "/" || c == "\u{00F7}" {
                    guard right.value != 0 else { throw CalculatorError.divisionByZero }
                    left = (left.value / right.value, false)
                } else {
                    left = (left.value * right.value, false)
                }
            }
            return left
        }

        private mutating func unary() throws -> (value: Double, percent: Bool) {
            if let c = peek(), c == "-" || c == "+" {
                try take()
                let v = try unary()
                return (c == "-" ? -v.value : v.value, v.percent)
            }
            return try power()
        }

        private mutating func power() throws -> (value: Double, percent: Bool) {
            let base = try postfix()
            if let c = peek(), c == "^" {
                try take()
                let exp = try unary()
                return (Foundation.pow(base.value, exp.value), false)
            }
            return base
        }

        private mutating func postfix() throws -> (value: Double, percent: Bool) {
            var v = try primary()
            var percent = false
            while let c = peek(), c == "%" {
                try take()
                v /= 100
                percent = true
            }
            return (v, percent)
        }

        private mutating func primary() throws -> Double {
            guard let c = peek() else { throw CalculatorError.syntax }
            if c == "(" {
                try take()
                let v = try expr().value
                guard let close = peek(), close == ")" else { throw CalculatorError.syntax }
                try take()
                return v
            }
            return try number()
        }

        private mutating func number() throws -> Double {
            var text = ""
            var seenSeparator = false
            while pos < chars.count {
                let c = chars[pos]
                if c.isASCII && c.isNumber { text.append(c) } else if c == "." || c == "," {
                    if seenSeparator { throw CalculatorError.syntax }
                    seenSeparator = true
                    text.append(".")
                } else { break }
                pos += 1
            }
            tokens += 1
            guard tokens <= Calculator.maxTokens else { throw CalculatorError.tooComplex }
            guard !text.isEmpty, text != ".", let v = Double(text) else { throw CalculatorError.syntax }
            return v
        }
    }
}

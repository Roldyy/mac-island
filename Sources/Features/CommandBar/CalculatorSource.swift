import Foundation

struct CalculatorSource: ResultSource {
    let sourceID = "calculator"
    var locale: Locale = .current

    func results(for query: String) async -> [BarResult] {
        guard Calculator.looksLikeExpression(query), case .success(let v) = Calculator.evaluate(query) else { return [] }
        let text = Calculator.format(v, locale: locale)
        return [BarResult(id: "calc", title: "= \(text)", subtitle: "Calcul : Entr\u{00E9}e copie le r\u{00E9}sultat",
                          kind: .calculator, action: .copy(text), fixedScore: 1000)]
    }
}

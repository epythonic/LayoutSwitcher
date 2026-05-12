import Foundation

/// Character-bigram language model with add-one Laplace smoothing.
struct NGramModel {
    static let boundary: Character = "^"
    static let alpha: Double = 1.0

    let language: LanguageID
    private let bigramCount: [String: Int]
    private let unigramCount: [Character: Int]
    private let vocabularySize: Int

    /// Trains model counts from corpus words.
    init(language: LanguageID, corpus: some Sequence<String>) {
        self.language = language
        var bigrams: [String: Int] = [:]
        var unigrams: [Character: Int] = [:]
        var vocab: Set<Character> = []

        for raw in corpus {
            let word = NGramModel.normalize(raw)
            guard !word.isEmpty else { continue }
            let padded: [Character] = [Self.boundary] + Array(word) + [Self.boundary]
            for i in 0..<(padded.count - 1) {
                let a = padded[i]
                let b = padded[i + 1]
                let key = "\(a)\(b)"
                bigrams[key, default: 0] += 1
                unigrams[a, default: 0] += 1
                vocab.insert(a)
                vocab.insert(b)
            }
        }
        self.bigramCount = bigrams
        self.unigramCount = unigrams
        self.vocabularySize = max(vocab.count, 1)
    }

    /// Average log-probability per bigram. Higher = better fit for this language.
    func score(_ rawWord: String) -> Double {
        let word = NGramModel.normalize(rawWord)
        guard !word.isEmpty else { return -Double.infinity }
        let padded: [Character] = [Self.boundary] + Array(word) + [Self.boundary]
        var total: Double = 0
        var pairs = 0
        for i in 0..<(padded.count - 1) {
            let a = padded[i]
            let b = padded[i + 1]
            total += logProbability(a, b)
            pairs += 1
        }
        return pairs > 0 ? total / Double(pairs) : -Double.infinity
    }

    /// Computes smoothed conditional log-probability for one character pair.
    private func logProbability(_ a: Character, _ b: Character) -> Double {
        let bigram = bigramCount["\(a)\(b)"] ?? 0
        let denom = (unigramCount[a] ?? 0) + Int(NGramModel.alpha * Double(vocabularySize))
        let numerator = Double(bigram) + NGramModel.alpha
        return log(numerator / Double(denom))
    }

    /// Shared normalization pipeline used for corpus and inference words.
    static func normalize(_ word: String) -> String {
        var result = word.lowercased()
        result = result.replacingOccurrences(of: "ё", with: "е")
        return result
    }
}

/// Factory namespace for prebuilt language models from embedded corpora.
enum NGramModels {
    /// English model trained on the stable frequency corpus, NOT the lookup dict.
    /// This insulates ngram statistics from growth of `EmbeddedDictionaries.english()`.
    static func english() -> NGramModel {
        NGramModel(language: .en, corpus: EmbeddedDictionaries.enNgramCorpus)
    }

    /// Russian model trained on the stable frequency corpus, NOT the lookup dict.
    static func russian() -> NGramModel {
        NGramModel(language: .ru, corpus: EmbeddedDictionaries.ruNgramCorpus)
    }

    /// Ukrainian model trained on the stable frequency corpus, NOT the lookup dict.
    static func ukrainian() -> NGramModel {
        NGramModel(language: .uk, corpus: EmbeddedDictionaries.ukNgramCorpus)
    }

    /// Romanian model trained on the stable frequency corpus, NOT the lookup dict.
    static func romanian() -> NGramModel {
        NGramModel(language: .ro, corpus: EmbeddedDictionaries.roNgramCorpus)
    }
}

extension InMemoryDictionary {
    /// Exposes all words for downstream consumers (n-gram trainers).
    var allWords: [String] { Array(self.wordsExposedForNGram) }
}

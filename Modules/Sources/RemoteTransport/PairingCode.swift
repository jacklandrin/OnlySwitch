public enum PairingCode {
    public static let length = 12

    private static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    public static func generate<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        String((0..<length).map { _ in
            alphabet[Int.random(in: alphabet.indices, using: &generator)]
        })
    }
}

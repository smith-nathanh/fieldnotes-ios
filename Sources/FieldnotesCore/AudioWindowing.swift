import Foundation

public enum AudioWindowing {
    public static func splitSignal(
        _ samples: [Float],
        sampleRate: Int,
        overlapSeconds: Double,
        chunkSeconds: Double = 3,
        minimumSeconds: Double = 1.5
    ) -> [[Float]] {
        precondition(sampleRate > 0)
        precondition(chunkSeconds > overlapSeconds)

        let chunkLength = Int(chunkSeconds * Double(sampleRate))
        let minimumLength = Int(minimumSeconds * Double(sampleRate))
        let strideLength = Int((chunkSeconds - overlapSeconds) * Double(sampleRate))

        var chunks: [[Float]] = []
        var index = 0

        while index < samples.count {
            let end = min(index + chunkLength, samples.count)
            let available = end - index
            if available < minimumLength {
                break
            }

            var chunk = Array(samples[index..<end])
            if chunk.count < chunkLength {
                chunk.append(contentsOf: repeatElement(0, count: chunkLength - chunk.count))
            }
            chunks.append(chunk)
            index += strideLength
        }

        return chunks
    }
}

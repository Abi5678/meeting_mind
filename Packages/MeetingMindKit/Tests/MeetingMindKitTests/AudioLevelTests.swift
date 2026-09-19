import Testing
@testable import MeetingMindKit

@Suite("Audio level metering")
struct AudioLevelTests {
    @Test("Silence and room noise read as zero")
    func silence() {
        #expect(AudioRecorderService.normalizedLevel(decibels: -160) == 0)
        #expect(AudioRecorderService.normalizedLevel(decibels: -50) == 0)
        #expect(AudioRecorderService.normalizedLevel(decibels: -.infinity) == 0)
        #expect(AudioRecorderService.normalizedLevel(decibels: .nan) == 0)
    }

    @Test("Full scale reads as one and never exceeds it")
    func fullScale() {
        #expect(AudioRecorderService.normalizedLevel(decibels: 0) == 1)
        #expect(AudioRecorderService.normalizedLevel(decibels: 3) == 1)
    }

    @Test("Louder input gives a higher level")
    func monotonic() {
        let quiet = AudioRecorderService.normalizedLevel(decibels: -40)
        let speech = AudioRecorderService.normalizedLevel(decibels: -20)
        #expect(0 < quiet && quiet < speech && speech < 1)
    }
}

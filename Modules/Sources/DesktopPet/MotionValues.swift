struct MotionValues {
    let verticalOffset: Double
    let eyeScale: Double
    let sliderOffset: Double

    static let still = MotionValues(
        verticalOffset: 0,
        eyeScale: 1,
        sliderOffset: 0
    )
}

//
//  Modulate.swift
//  Squirrel2
//
//  Utility for interpolating values between ranges
//

import SwiftUI

/// Interpolates a value from one range to another (equivalent to Framer's modulate)
/// - Parameters:
///   - value: The input value to interpolate
///   - inputRange: The input range [min, max]
///   - outputRange: The output range [min, max]
///   - limit: Whether to clamp the result within the output range
/// - Returns: The interpolated value
func modulate(_ value: CGFloat, from inputRange: [CGFloat], to outputRange: [CGFloat], limit: Bool = true) -> CGFloat {
    guard inputRange.count == 2, outputRange.count == 2 else { return value }
    
    let fromLow = inputRange[0]
    let fromHigh = inputRange[1]
    let toLow = outputRange[0]
    let toHigh = outputRange[1]
    
    let result = toLow + ((value - fromLow) / (fromHigh - fromLow)) * (toHigh - toLow)
    
    if limit {
        if toLow < toHigh {
            return min(max(result, toLow), toHigh)
        } else {
            return min(max(result, toHigh), toLow)
        }
    }
    
    return result
}

/// ViewModifier to track navigation presentation progress
struct NavigationProgressTracker: ViewModifier {
    @Binding var progress: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: NavigationProgressKey.self, value: geometry.frame(in: .global).minY)
                }
            )
            .onPreferenceChange(NavigationProgressKey.self) { value in
                // Convert the Y position to a 0-1 progress value
                // When fully presented, minY = 0
                // When dismissing, minY increases
                let screenHeight = UIScreen.main.bounds.height
                progress = 1.0 - min(max(value / screenHeight, 0), 1)
            }
    }
}

struct NavigationProgressKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
//
//  MultiplatformExtensions.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI

#if !os(tvOS)
extension View {
    /// Non-tvOS compatibility shim for tvOS focusSection modifier
    @ViewBuilder
    func focusSection() -> some View {
        self
    }
}
#endif

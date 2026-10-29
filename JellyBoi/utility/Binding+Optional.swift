//
//  Binding+Optional.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/29/26.
//

import SwiftUI

extension Binding where Value == Bool {
    /// Creates a boolean binding from an optional binding.
    /// Returns `true` when the underlying value is non-nil, and sets it to `nil` when set to `false`.
    init<Wrapped>(_ source: Binding<Wrapped?>) {
        self.init(
            get: { source.wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    source.wrappedValue = nil
                }
            }
        )
    }
}

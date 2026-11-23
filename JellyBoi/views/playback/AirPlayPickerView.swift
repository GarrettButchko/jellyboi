//
//  AirPlayPickerView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/22/26.
//

import SwiftUI
import AVKit

struct AirPlayPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = .white
        routePicker.activeTintColor = .white
        routePicker.prioritizesVideoDevices = true
        routePicker.backgroundColor = .clear
        return routePicker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

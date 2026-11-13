//
//  OrDivider.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/26/26.
//

import SwiftUI
import BaseColors

struct OrDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.mainOpp.opacity(0.15))
                .frame(height: 1)
            Text("or")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.4))
            Rectangle()
                .fill(Color.mainOpp.opacity(0.15))
                .frame(height: 1)
        }
    }
}

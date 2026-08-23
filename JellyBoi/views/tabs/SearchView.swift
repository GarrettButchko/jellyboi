//
//  SearchView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

struct SearchView: View {
    var body: some View {
        Text("Search")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                ProfileAvatarButton()
            }
    }
}

#Preview {
    SearchView()
}

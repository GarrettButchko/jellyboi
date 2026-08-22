//
//  TabsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

struct TabsView: View {

    @EnvironmentObject var viewManager: ViewManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            MediaView()
                .tabItem {
                    Label("Media", systemImage: "rectangle.stack")
                }

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
        }
    }
}

#Preview {
    TabsView()
        .environmentObject(ViewManager())
}

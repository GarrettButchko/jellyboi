//
//  SignInView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

struct SignInView: View {

    @EnvironmentObject var viewManager: ViewManager

    var body: some View {
        Text("Sign In")
    }
}

#Preview {
    SignInView()
        .environmentObject(ViewManager())
}

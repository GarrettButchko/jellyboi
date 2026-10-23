//
//  JellyBoiWidgetExtensionBundle.swift
//  JellyBoiWidgetExtension
//
//  Created by Garrett Butchko on 10/20/26.
//

import WidgetKit
import SwiftUI

@main
struct JellyBoiWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        JellyBoiWidgetExtension()
        DownloadActivityWidget()
    }
}

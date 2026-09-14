//
//  SceneDelegate.swift
//  Instant Notes
//
// Minimal scene delegate wired from Info.plist.
// On iOS 17+ most behavior lives in the App struct, but we keep this to match the plist config.

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let _ = (scene as? UIWindowScene) else { return }
    }
}

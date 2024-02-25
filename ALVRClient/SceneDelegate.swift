//
//  MyAppDelegate.swift
//  HelloCardboard
//
//  Created by Viktor Varenik on 25.02.2024.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate, UINavigationControllerDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = (scene as? UIWindowScene) else { return }
        
        let window = UIWindow(windowScene: scene)
        
        let viewController = MainViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.delegate = self
        navigationController.isNavigationBarHidden = true
        
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        
        self.window = window
    }
    
    func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
        return navigationController.topViewController!.supportedInterfaceOrientations;
    }

    func sceneDidDisconnect(_ scene: UIScene) { }

    func sceneDidBecomeActive(_ scene: UIScene) { }

    func sceneWillResignActive(_ scene: UIScene) { }

    func sceneWillEnterForeground(_ scene: UIScene) { }

    func sceneDidEnterBackground(_ scene: UIScene) { }
}

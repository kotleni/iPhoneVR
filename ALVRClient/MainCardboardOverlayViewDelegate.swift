//
//  MainCardboardOverlayViewDelegate.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 25.02.2024.
//

import UIKit

protocol MainCardboardOverlayViewDelegate: AnyObject {
    func didTapTriggerButton()
    func didTapBackButton()
    func presentingViewControllerForSettingsDialog() -> UIViewController?
    func didPresentSettingsDialog(_ presented: Bool)
    func didChangeViewerProfile()
}

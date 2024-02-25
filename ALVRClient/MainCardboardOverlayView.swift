//
//  MainCardboardOverlayView.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 25.02.2024.
//

import UIKit

let kMenuButtonContentPadding = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
let kMenuButtonImagePadding = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
let kMenuButtonTitlePadding = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 16)
let kMenuSheetBottomPadding: CGFloat = 8

let kDefaultDpi: CGFloat = 326.0
let kIPhone6PlusDpi: CGFloat = 401.0
let kMetersPerInch: CGFloat = 0.0254

let kAlignmentMarkerHeight6Plus = (28.0 / (kMetersPerInch * 1000)) * kIPhone6PlusDpi / 3
let kAlignmentMarkerHeight = (28.0 / (kMetersPerInch * 1000)) * kDefaultDpi / 2

class MainCardboardOverlayView: UIView {
    private var alignmentMarker: UIView!
    private var overlayInsetView: UIView!
    private var backButton: UIButton!
    private var menuButtonsBackgroundView: UIView!
    private var menuButtonsInsetView: UIView!
    private var settingsButton: UIButton!
    private var switchButton: UIButton!
    private var settingsBackgroundView: UIView!
    
    weak var delegate: MainCardboardOverlayViewDelegate?

    var hidesAlignmentMarker: Bool = false
    var hidesBackButton: Bool = false
    var hidesSettingsButton: Bool = false
    var hidesTransitionView: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit(frame: frame, createTransitionView: true)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit(frame: .zero, createTransitionView: false)
    }

    init(frame: CGRect, createTransitionView: Bool) {
        super.init(frame: frame)
        commonInit(frame: frame, createTransitionView: createTransitionView)
    }

    private func commonInit(frame: CGRect, createTransitionView: Bool) {
        let viewBounds = bounds
        let insets = MainCardboardOverlayView.landscapeModeSafeAreaInsets()

        // Alignment marker.
        alignmentMarker = UIView()
        alignmentMarker.backgroundColor = UIColor(white: 1.0, alpha: 0.7)
        addSubview(alignmentMarker)

        overlayInsetView = UIView()
        overlayInsetView.frame = viewBounds.inset(by: insets)
        addSubview(overlayInsetView)

        let overlayInsetBounds = overlayInsetView.bounds

        // We should always be fullscreen.
        autoresizingMask = [.flexibleHeight, .flexibleWidth]

        // Settings button.
        let settingsImage = UIImage(named: "HelloCardboard.bundle/ic_settings_white", in: nil, compatibleWith: nil)
        settingsButton = UIButton(type: .roundedRect)
        settingsButton.tintColor = UIColor.white
        settingsButton.setImage(settingsImage, for: .normal)
        settingsButton.addTarget(self, action: #selector(didTapSettingsButton(_:)), for: .touchUpInside)
        settingsButton.sizeToFit()
        let bounds = settingsButton.bounds
        settingsButton.frame = CGRect(x: CGRectGetWidth(overlayInsetBounds) - CGRectGetWidth(bounds),
                                      y: 0, width: CGRectGetWidth(bounds), height: CGRectGetHeight(bounds))
        settingsButton.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        overlayInsetView.addSubview(settingsButton)

        // Back button.
        backButton = UIButton(type: .roundedRect)
        backButton.tintColor = UIColor.white
        backButton.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        backButton.setImage(UIImage(named: "HelloCardboard.bundle/ic_arrow_back_ios_white", in: nil, compatibleWith: nil),
                            for: .normal)
        backButton.addTarget(self, action: #selector(didTapBackButton(_:)), for: .touchUpInside)
        backButton.sizeToFit()
        overlayInsetView.addSubview(backButton)

        // Settings background view.
        settingsBackgroundView = UIView(frame: frame)
        settingsBackgroundView.backgroundColor = UIColor(white: 0, alpha: 0.65)
        settingsBackgroundView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        settingsBackgroundView.isHidden = true
        addSubview(settingsBackgroundView)

        // Add tap gesture to dismiss the settings view.
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapSettingsBackgroundView(_:)))
        settingsBackgroundView.addGestureRecognizer(tapGesture)

        // Switch menu button.
        let cardboardImage = UIImage(named: "HelloCardboard.bundle/ic_cardboard", in: nil, compatibleWith: nil)
        let title = "Switch Cardboard viewer"
        switchButton = menuButtonWithTitle(title: title, image: cardboardImage, placedBelowView: nil)
        switchButton.addTarget(self, action: #selector(didTapSwitchButton(_:)), for: .touchUpInside)

        // Button background view.
        menuButtonsBackgroundView = UIView()
        menuButtonsBackgroundView.backgroundColor = UIColor(white: 0, alpha: 0.65)
        let backgroundHeight = CGRectGetHeight(switchButton.frame) + kMenuSheetBottomPadding
        menuButtonsBackgroundView.frame = CGRect(x: 0, y: CGRectGetHeight(viewBounds) - backgroundHeight,
                                                  width: CGRectGetWidth(viewBounds), height: backgroundHeight)
        menuButtonsBackgroundView.autoresizingMask = [.flexibleTopMargin, .flexibleWidth]
        settingsBackgroundView.addSubview(menuButtonsBackgroundView)

        menuButtonsInsetView = UIView()
        updateMenuButtonsInsetViewFrame()
        menuButtonsBackgroundView.addSubview(menuButtonsInsetView)

        menuButtonsInsetView.addSubview(switchButton)
        
        accessibilityIdentifier = "overlay_view"
    }

    @objc func didTapBackButton(_ sender: Any) {
        delegate?.didTapBackButton()
    }

    @objc func didTapSettingsButton(_ sender: Any) {
        settingsBackgroundView.isHidden = false
    }

    @objc func didTapSettingsBackgroundView(_ sender: Any) {
        settingsBackgroundView.isHidden = true
    }

    @objc func didTapSwitchButton(_ sender: Any) {
        delegate?.didChangeViewerProfile()
        settingsBackgroundView.isHidden = true
    }

    func didTapBackButton() {
        // FIXME: didTapBackButton(nil)
    }

    func menuButtonWithTitle(title: String, image: UIImage?, placedBelowView aboveView: UIView?) -> UIButton {
        let button = UIButton(type: .custom)
        button.contentHorizontalAlignment = .left
        button.imageEdgeInsets = kMenuButtonImagePadding
        button.titleEdgeInsets = kMenuButtonTitlePadding
        button.contentEdgeInsets = kMenuButtonContentPadding
        button.setTitle(title, for: .normal)
        button.setImage(image, for: .normal)
        button.sizeToFit()
        button.frame = CGRect(x: 0, y: CGRectGetMaxY(aboveView?.frame ?? CGRect.zero),
                              width: CGRectGetWidth(bounds), height: CGRectGetHeight(button.bounds))
        button.autoresizingMask = [.flexibleTopMargin, .flexibleWidth]
        return button
    }

    func updateMenuButtonsInsetViewFrame() {
        var menuButtonsInsets = MainCardboardOverlayView.landscapeModeSafeAreaInsets()
        // The menu buttons are a menu at the bottom of the screen.
        menuButtonsInsets.top = 0
        menuButtonsInsetView.frame = menuButtonsBackgroundView.bounds.inset(by: menuButtonsInsets)
    }

    class func appName() -> String {
        let localizedInfoDictionary = Bundle.main.localizedInfoDictionary
        let bundleDisplayName = localizedInfoDictionary?["CFBundleDisplayName"] as? String
        if let bundleDisplayName = bundleDisplayName {
            return bundleDisplayName
        }
        let bundleName = localizedInfoDictionary?[kCFBundleNameKey as String] as? String
        if let bundleName = bundleName {
            return bundleName
        }
        return ProcessInfo.processInfo.processName
    }

    class func landscapeModeSafeAreaInsets() -> UIEdgeInsets {
        return UIApplication.shared.keyWindow?.safeAreaInsets ?? UIEdgeInsets.zero
    }

    class func alignmentMarkerHeight() -> CGFloat {
        let iphone6plus = UIScreen.main.scale > 2
        let height = iphone6plus ? kAlignmentMarkerHeight6Plus : kAlignmentMarkerHeight
        return height
    }
}

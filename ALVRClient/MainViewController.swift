//
//  MainViewController.swift
//  HelloCardboard
//
//  Created by Viktor Varenik on 25.02.2024.
//

import UIKit
import GLKit

class MainViewController: GLKViewController, GLKViewControllerDelegate, MainCardboardOverlayViewDelegate {
    func didTapTriggerButton() {
        print("didTapTriggerButton")
    }
    
    func presentingViewControllerForSettingsDialog() -> UIViewController? {
        fatalError("Not implemented yet.")
    }

    //var cardboardLensDistortion: CardboardLensDistortion?
//    var cardboardHeadTracker: CardboardHeadTracker?
    //var renderer: cardboard.hello_cardboard.HelloCardboardRenderer?
    var deviceParamsChangedCount: Int = -1

    deinit {
//        CardboardLensDistortion_destroy(cardboardLensDistortion)
//        CardboardHeadTracker_destroy(cardboardHeadTracker)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self

        // Create an overlay view on top of the GLKView.
        let overlayView = MainCardboardOverlayView(frame: self.view.bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.delegate = self
        self.view.addSubview(overlayView)

        // Add a tap gesture to handle viewer trigger action.
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapGLView(_:)))
        self.view.addGestureRecognizer(tapGesture)

        // Prevents screen to turn off.
        UIApplication.shared.isIdleTimerDisabled = true

        // Create an OpenGL ES context and assign it to the view loaded from storyboard.
        if let glkView = self.view as? GLKView {
            glkView.context = EAGLContext(api: .openGLES3)!
            EAGLContext.setCurrent(glkView.context)
        }

        // Set animation frame rate.
        self.preferredFramesPerSecond = 60

        // Set the GL context.
//        EAGLContext.setCurrent(glkView)
//
//        // Make sure the glkView has bound its offscreen buffers before calling into cardboard.
//        glkView.bindDrawable()

        // Create cardboard head tracker.
//        cardboardHeadTracker = CardboardHeadTracker_create()
//        cardboardLensDistortion = nil

        // Set the counter to -1 to force a device params update.
        deviceParamsChangedCount = -1
        
        view.backgroundColor = .red
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if #available(iOS 11.0, *) {
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
        resumeCardboard()
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Cardboard only supports landscape right orientation for inserting the phone in the viewer.
        return .landscapeRight
    }

    override func glkView(_ view: GLKView, drawIn rect: CGRect) {
        if !updateDeviceParams() {
            return
        }
        //renderer?.DrawFrame()
    }

    func glkViewControllerUpdate(_ controller: GLKViewController) {
        // Perform GL state update before drawing.
    }

    func deviceParamsChanged() -> Bool {
        return deviceParamsChangedCount != CardboardQrCode_getDeviceParamsChangedCount()
    }

    func updateDeviceParams() -> Bool {
        // Check if device parameters have changed.
        guard !deviceParamsChanged() else {
            print()
            return true
        }

        var encodedDeviceParams: UnsafeMutablePointer<UInt8>?
        var size: Int32 = 0
        CardboardQrCode_getSavedDeviceParams(&encodedDeviceParams, &size)

        guard size > 0 else {
            print("Saved device params has 0 size.")
            return false
        }

        // Using native scale as we are rendering directly to the screen.
        let screenRect = self.view.bounds
        let screenScale = UIScreen.main.nativeScale
        var height = Int32(screenRect.size.height * screenScale)
        var width = Int32(screenRect.size.width * screenScale)

        // Rendering coordinates assume landscape orientation.
        if height > width {
            let temp = height
            height = width
            width = temp
        }

        // Create CardboardLensDistortion.
//        CardboardLensDistortion_destroy(cardboardLensDistortion)
//        cardboardLensDistortion = CardboardLensDistortion_create(encodedDeviceParams, size, width, height)

        // Initialize HelloCardboardRenderer.
//        renderer = cardboard.hello_cardboard.HelloCardboardRenderer(cardboardLensDistortion, cardboardHeadTracker, width, height)
//        renderer?.InitializeGl()

        CardboardQrCode_destroy(encodedDeviceParams)

        deviceParamsChangedCount = Int(CardboardQrCode_getDeviceParamsChangedCount())

        return true
    }

    func pauseCardboard() {
        self.isPaused = true
        //CardboardHeadTracker_pause(cardboardHeadTracker)
    }

    func resumeCardboard() {
        var buffer: UnsafeMutablePointer<UInt8>?
        var size: Int32 = 0
        CardboardQrCode_getSavedDeviceParams(&buffer, &size)
        if size == 0 {
            print(size)
            switchViewer()
        }
        CardboardQrCode_destroy(buffer)

        //CardboardHeadTracker_resume(cardboardHeadTracker)
        self.isPaused = false
    }

    func switchViewer() {
        CardboardQrCode_scanQrCodeAndSaveDeviceParams()
    }

    @objc func didTapGLView(_ sender: Any) {
        //renderer?.OnTriggerEvent()
    }

    func didTapBackButton() {
        // User pressed the back button. Pop this view controller.
        print("User pressed back button")
    }

    func didPresentSettingsDialog(_ presented: Bool) {
        // The overlay view is presenting the settings dialog. Pause our rendering while presented.
        self.isPaused = presented
    }

    func didChangeViewerProfile() {
        pauseCardboard()
        switchViewer()
        resumeCardboard()
    }
}


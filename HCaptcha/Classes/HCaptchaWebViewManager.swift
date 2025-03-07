//
//  HCaptchaWebViewManager.swift
//  HCaptcha
//
//  Created by Flávio Caetano on 22/03/17.
//  Copyright © 2018 HCaptcha. All rights reserved.
//

import Foundation
import WebKit


/** Handles comunications with the webview containing the HCaptcha challenge.
 */
internal class HCaptchaWebViewManager {
    enum JSCommand: String {
        case execute = "execute();"
        case reset = "reset();"
    }

    fileprivate struct Constants {
        static let ExecuteJSCommand = "execute();"
        static let ResetCommand = "reset();"
        static let BotUserAgent = "bot/2.1"
    }

#if DEBUG
    /// Forces the challenge to be explicitly displayed.
    var forceVisibleChallenge = false {
        didSet {
            // Also works on iOS < 9
            webView.performSelector(
                onMainThread: "_setCustomUserAgent:",
                with: forceVisibleChallenge ? Constants.BotUserAgent : nil,
                waitUntilDone: true
            )
        }
    }

    /// Allows validation stubbing for testing
    public var shouldSkipForTests = false
#endif

    /// Sends the result message
    var completion: ((HCaptchaResult) -> Void)?

    /// Notifies the JS bundle has finished loading
    var onDidFinishLoading: (() -> Void)? {
        didSet {
            if didFinishLoading {
                onDidFinishLoading?()
            }
        }
    }

    /// Configures the webview for display when required
    var configureWebView: ((WKWebView) -> Void)?

    /// The dispatch token used to ensure `configureWebView` is only called once.
    var configureWebViewDispatchToken = UUID()

    /// If the HCaptcha should be reset when it errors
    var shouldResetOnError = true

    /// The JS message recoder
    fileprivate var decoder: HCaptchaDecoder!

    /// Indicates if the script has already been loaded by the `webView`
    fileprivate var didFinishLoading = false {
        didSet {
            if didFinishLoading {
                onDidFinishLoading?()
            }
        }
    }

    /// The observer for `.UIWindowDidBecomeVisible`
    fileprivate var observer: NSObjectProtocol?

    /// The endpoint url being used
    fileprivate var endpoint: String

    /// The webview that executes JS code
    lazy var webView: WKWebView = {
        let webview = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            configuration: self.buildConfiguration()
        )
        webview.accessibilityIdentifier = "webview"
        webview.accessibilityTraits = UIAccessibilityTraits.link
        webview.isHidden = true

        return webview
    }()

    /**
     - parameters:
         - html: The HTML string to be loaded onto the webview
         - apiKey: The hCaptcha sitekey
         - baseURL: The URL configured with the sitekey
         - endpoint: The JS API endpoint to be loaded onto the HTML file.
         - size: Size of visible area
         - rqdata: Custom supplied challenge data
         - theme: Widget theme, value must be valid JS Object or String with brackets
     */
    init(html: String, apiKey: String, baseURL: URL, endpoint: URL,
         size: Size, rqdata: String?, theme: String) {
        self.endpoint = endpoint.absoluteString
        self.decoder = HCaptchaDecoder { [weak self] result in
            self?.handle(result: result)
        }

        let formattedHTML = String(format: html, arguments: ["apiKey": apiKey,
                                                             "endpoint": self.endpoint,
                                                             "size": size.rawValue,
                                                             "rqdata": rqdata ?? "",
                                                             "theme": theme])

        if let window = UIApplication.shared.keyWindow {
            setupWebview(on: window, html: formattedHTML, url: baseURL)
        }
        else {
            observer = NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeVisibleNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let window = notification.object as? UIWindow else { return }
                self?.setupWebview(on: window, html: formattedHTML, url: baseURL)
            }
        }
    }

    /**
     - parameter view: The view that should present the webview.

     Starts the challenge validation
     */
     func validate(on view: UIView) {
#if DEBUG
        guard !shouldSkipForTests else {
            completion?(.token(""))
            return
        }
#endif
        webView.isHidden = false
        view.addSubview(webView)

        executeJS(command: .execute)
    }


    /// Stops the execution of the webview
    func stop() {
        webView.stopLoading()
    }

    /**
     Resets the HCaptcha.

     The reset is achieved by calling `ghcaptcha.reset()` on the JS API.
     */
    func reset() {
        configureWebViewDispatchToken = UUID()
        executeJS(command: .reset)
        didFinishLoading = false
    }
}

// MARK: - Private Methods

/** Private methods for HCaptchaWebViewManager
 */
fileprivate extension HCaptchaWebViewManager {
    /**
     - returns: An instance of `WKWebViewConfiguration`

     Creates a `WKWebViewConfiguration` to be added to the `WKWebView` instance.
     */
    func buildConfiguration() -> WKWebViewConfiguration {
        let controller = WKUserContentController()
        controller.add(decoder, name: "hcaptcha")

        let conf = WKWebViewConfiguration()
        conf.userContentController = controller

        return conf
    }

    /**
     - parameter result: A `HCaptchaDecoder.Result` with the decoded message.

     Handles the decoder results received from the webview
     */
    func handle(result: HCaptchaDecoder.Result) {
        switch result {
        case .token(let token):
            completion?(.token(token))

        case .error(let error):
            handle(error: error)

        case .showHCaptcha:
            DispatchQueue.once(token: configureWebViewDispatchToken) { [weak self] in
                guard let `self` = self else { return }
                self.configureWebView?(self.webView)
            }

        case .didLoad:
            didFinishLoading = true
            if completion != nil {
                executeJS(command: .execute)
            }

        case .log(let message):
            #if DEBUG
                print("[JS LOG]:", message)
            #endif
        }
    }

    private func handle(error: HCaptchaError) {
        if case HCaptchaError.userClosed = error {
            completion?(.error(error))
            return
        }

        if shouldResetOnError, let view = webView.superview {
            reset()
            validate(on: view)
        }
        else {
            completion?(.error(error))
        }
    }

    /**
     - parameters:
         - window: The window in which to add the webview
         - html: The embedded HTML file
         - url: The base URL given to the webview

     Adds the webview to a valid UIView and loads the initial HTML file
     */
    func setupWebview(on window: UIWindow, html: String, url: URL) {
        window.addSubview(webView)
        webView.loadHTMLString(html, baseURL: url)

        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /**
     - parameters:
         - command: The JavaScript command to be executed

     Executes the JS command that loads the HCaptcha challenge. This method has no effect if the webview hasn't
     finished loading.
     */
    func executeJS(command: JSCommand) {
        guard didFinishLoading else {
            // Hasn't finished loading all the resources
            return
        }

        webView.evaluateJavaScript(command.rawValue) { [weak self] _, error in
            if let error = error {
                self?.decoder.send(error: .unexpected(error))
            }
        }
    }
}

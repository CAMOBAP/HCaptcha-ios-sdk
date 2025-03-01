//
//  HCaptchaWebViewManager+Helpers.swift
//  HCaptcha
//
//  Created by Flávio Caetano on 13/04/17.
//  Copyright © 2018 HCaptcha. All rights reserved.
//

import Foundation
@testable import HCaptcha
import WebKit

extension HCaptchaWebViewManager {
    private static let unformattedHTML: String! = {
        Bundle(for: HCaptchaWebViewManager__Tests.self)
            .path(forResource: "mock", ofType: "html")
            .flatMap { try? String(contentsOfFile: $0) }
    }()

    convenience init(
        messageBody: String = "",
        apiKey: String? = nil,
        endpoint: URL? = nil,
        shouldFail: Bool = false,
        size: Size = .invisible,
        rqdata: String? = nil,
        theme: String = "\"light\""
    ) {
        let html = String(format: HCaptchaWebViewManager.unformattedHTML,
                          arguments: [
                            "message": messageBody,
                            "shouldFail": shouldFail.description
                          ])

        self.init(
            html: html,
            apiKey: apiKey,
            endpoint: endpoint,
            size: size,
            rqdata: rqdata,
            theme: theme
        )
    }

    convenience init(
        html: String,
        apiKey: String? = nil,
        endpoint: URL? = nil,
        size: Size = .invisible,
        rqdata: String? = nil,
        theme: String = "\"light\""
    ) {
        let localhost = URL(string: "http://localhost")!

        self.init(
            html: html,
            apiKey: apiKey ?? String(arc4random()),
            baseURL: localhost,
            endpoint: endpoint ?? localhost,
            size: size,
            rqdata: rqdata,
            theme: theme
        )
    }

    func configureWebView(_ configure: @escaping (WKWebView) -> Void) {
        configureWebView = configure
    }

    func validate(on view: UIView, resetOnError: Bool = true, completion: @escaping (HCaptchaResult) -> Void) {
        self.shouldResetOnError = resetOnError
        self.completion = completion

        validate(on: view)
    }
}

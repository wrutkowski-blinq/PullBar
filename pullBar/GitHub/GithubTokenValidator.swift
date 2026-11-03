//
//  TokenStatus.swift
//  pullBar
//
//  Created by Pavel Makhov on 2022-08-13.
//

import Foundation
import SwiftUI

class GithubTokenValidator: ObservableObject {
    
    @Published var iconName: String!;
    @Published var iconColor: Color!;
    @Published var message = ""

    init() {
        setLoading()
    }

    func setLoading() {

        self.iconName = "clock.fill"
        self.iconColor = Color(.systemGray)
        self.message = "Checking…"
    }

    func setInvalid(message: String) {
        self.iconName = "exclamationmark.circle.fill"
        self.iconColor = Color(.systemRed)
        self.message = message
    }

    func setValid(login: String) {
        self.iconName = "checkmark.circle.fill"
        self.iconColor = Color(.systemGreen)
        self.message = "Signed in as \(login)"
    }

    func validate() {
        self.setLoading()

        if GhCli.token.isEmpty {
            self.setInvalid(message: "No token from gh for \(GhCli.hostname)")
            return
        }

        GitHubClient().getUser() { user in
            if let user = user {
                self.setValid(login: user.login)
            } else {
                self.setInvalid(message: "GitHub rejected the gh token")
            }
        }
    }
}

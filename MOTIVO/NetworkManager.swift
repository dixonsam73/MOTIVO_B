//
//  NetworkManager.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-NetworkManager-7c3d
//  SCOPE: v7.12C — placeholder singleton, no real networking
//

import Foundation

public final class NetworkManager {
    public static let shared = NetworkManager()
    private init() {}

    // Placeholder properties for future handshake
    public var baseURL: URL? = nil
    public var authToken: String? = nil

    public func configure(baseURL: URL?, authToken: String?) {
        self.baseURL = baseURL
        self.authToken = authToken
        print("[NetworkManager] configured baseURL=\(String(describing: baseURL)) token=\(authToken != nil ? "•••" : "nil")")
    }
}

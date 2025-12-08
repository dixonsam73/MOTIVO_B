// AudioServices.swift
import Foundation
import AVFoundation

@MainActor
final class AudioServices: ObservableObject {
    static let shared = AudioServices()

    let droneEngine: DroneEngine
    let metronomeEngine: MetronomeEngine

    private init() {
        self.droneEngine = DroneEngine()
        self.metronomeEngine = MetronomeEngine()
    }
}

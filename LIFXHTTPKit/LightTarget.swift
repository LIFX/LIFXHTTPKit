//
//  Created by Tate Johnson on 13/06/2015.
//  Copyright (c) 2015 Tate Johnson. All rights reserved.
//

import Foundation

public class LightTarget {
	internal typealias Filter = (light: Light) -> Bool

	private(set) var power: Bool
	private(set) var brightness: Double

	public let selector: String
	private let filter: Filter

	private var lights: [Light]
	private var observers: [LightTargetObserver]

	private unowned let client: Client
	private var clientObserver: ClientObserver!

	init(client: Client, selector: String, filter: Filter) {
		power = false
		brightness = 0.0

		self.selector = selector
		self.filter = filter

		lights = []
		observers = []

		self.client = client
		clientObserver = client.addObserver { [unowned self] (lights) in
			self.setLightsByApplyingFilter(lights)
		}

		setLightsByApplyingFilter(client.getLights())
	}

	deinit {
		client.removeObserver(clientObserver)
	}

	public func addObserver(stateDidUpdateHandler: LightTargetObserver.StateDidUpdate) -> LightTargetObserver {
		let observer = LightTargetObserver(stateDidUpdateHandler: stateDidUpdateHandler)
		observers.append(observer)
		return observer
	}

	public func removeObserver(observer: LightTargetObserver) {
		for (index, other) in enumerate(observers) {
			if other === observer {
				observers.removeAtIndex(index)
			}
		}
	}

	public func removeAllObservers() {
		observers = []
	}

	public func toLights() -> [Light] {
		return lights
	}

	public func setPower(power: Bool, duration: Float = 1.0) {
		setPower(power, duration: duration, completionHandler: nil)
	}

	public func setPower(power: Bool, duration: Float = 1.0, completionHandler: ((results: [Result], error: NSError?) -> Void)?) {
		self.power = power
		client.session.setLightsPower(selector, power: power, duration: duration) { [unowned self] (request, response, results, error) in
			if error == nil {
				self.client.updateLightsWithLights(self.lights.map { (light) in return light.lightWithPower(power) })
			}
			completionHandler?(results: results, error: error)
		}
	}

	private func setLightsByApplyingFilter(lights: [Light]) {
		self.lights = lights.filter(self.filter)
		dirtyCheck()
	}

	private func dirtyCheck() {
		var dirty = false

		let newPower = derivePower()
		if power != newPower {
			power = newPower
			dirty = true
		}

		let newBrightness = deriveBrightness()
		if brightness != newBrightness {
			brightness = newBrightness
			dirty = true
		}

		if dirty {
			for observer in observers {
				observer.stateDidUpdateHandler()
			}
		}
	}

	private func derivePower() -> Bool {
		for light in lights {
			if light.power {
				return true
			}
		}
		return false
	}

	private func deriveBrightness() -> Double {
		let count = lights.count
		if count > 0 {
			return lights.reduce(0.0) { (sum, light) in return light.brightness + sum } / Double(count)
		} else {
			return 0.0
		}
	}
}
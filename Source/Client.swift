//
//  Created by Tate Johnson on 29/05/2015.
//  Copyright (c) 2015 Tate Johnson. All rights reserved.
//

import Foundation

public class Client {
	public let session: HTTPSession
	public internal(set) var lights: [Light]
	public internal(set) var scenes: [Scene]
    public private(set) var themes: [Theme]
	private var observers: [ClientObserver]
	
    public convenience init(accessToken: String, lights: [Light]? = nil, scenes: [Scene]? = nil, themes: [Theme]? = nil) {
        self.init(session: HTTPSession(accessToken: accessToken), lights: lights, scenes: scenes, themes: themes)
	}
	
    public init(session: HTTPSession, lights: [Light]? = nil, scenes: [Scene]? = nil, themes: [Theme]? = nil) {
		self.session = session
		self.lights = lights ?? []
		self.scenes = scenes ?? []
        self.themes = themes ?? []
		observers = []
	}
	
	public func fetch(completionHandler: ((_ errors: [Error]) -> Void)? = nil) {
		let group = DispatchGroup()
		var errors: [Error] = []
		
		group.enter()
		fetchLights { (error) in
			if let error = error {
				errors.append(error)
			}
			group.leave()
		}
		
		group.enter()
		fetchScenes { (error) in
			if let error = error {
				errors.append(error)
			}
			group.leave()
		}
		
		group.notify(queue: session.delegateQueue) {
			completionHandler?(errors)
		}
	}
	
	public func fetchLights(completionHandler: ((_ error: Error?) -> Void)? = nil) {
        let requestedAt = Date()
		session.lights("all") { [weak self] (request, response, lights, error) in
			if error != nil {
				completionHandler?(error)
				return
			}
			
			if let strongSelf = self {
				let oldLights = strongSelf.lights
				var newLights = lights
				if oldLights != newLights {
                    newLights = newLights.map { newLight in
                        if let oldLight = oldLights.first(where: { $0.id == newLight.id }), oldLight.isDirty {
                            return oldLight.light(withUpdatedLight: newLight, requestedAt: requestedAt)
                        } else {
                            return newLight
                        }
                    }
                    strongSelf.lights = newLights
					for observer in strongSelf.observers {
						observer.lightsDidUpdateHandler(newLights)
					}
				}
				
			}
			
			completionHandler?(nil)
		}
	}
	
	public func fetchScenes(completionHandler: ((_ error: Error?) -> Void)? = nil) {
		session.scenes { [weak self] (request, response, scenes, error) in
			if error != nil {
				completionHandler?(error)
				return
			}
			
			self?.scenes = scenes
			
			completionHandler?(nil)
		}
	}
    
    public func fetchThemes(completionHandler: ((_ error: Error?) -> Void)? = nil) {
        session.curatedThemes { [weak self] (request, response, themes, error) in
            if error != nil {
                completionHandler?(error)
                return
            }
            
            self?.themes = themes
            
            completionHandler?(nil)
        }
    }
	
	public func allLightTarget() -> LightTarget {
		return lightTargetWithSelector(LightTargetSelector(type: .All))
	}
	
    /// Creates a target for API requests with the given selector. If an ID selector is specified and the Light is not already
    /// contained in the cache, then a placeholder light will be created so that events can be subscribed to.
    ///
    /// - Parameter selector: Selector referring to a Scene/Group/Light etc.
    /// - Returns: LightTarget which can be used to trigger API requests against the specified Selector
	public func lightTargetWithSelector(_ selector: LightTargetSelector) -> LightTarget {
        switch selector.type {
        case .ID:
            // Add light to cache if not already present
            updateLights([Light(id: selector.value, power: false, brightness: 0, color: Color(hue: 0, saturation: 0, kelvin: 3500), product: nil, label: "", connected: true, inFlightProperties: [], dirtyProperties: [])])
        default: break
        }
		return LightTarget(client: self, selector: selector, filter: selectorToFilter(selector))
	}
	
	func addObserver(lightsDidUpdateHandler: @escaping ClientObserver.LightsDidUpdate) -> ClientObserver {
		let observer = ClientObserver(lightsDidUpdateHandler: lightsDidUpdateHandler)
		observers.append(observer)
		return observer
	}
	
	func removeObserver(observer: ClientObserver) {
		for (index, other) in observers.enumerated() {
			if other === observer {
				observers.remove(at: index)
				break
			}
		}
	}
	
	func updateLights(_ lights: [Light]) {
		let oldLights = self.lights
		var newLights: [Light] = []
		
		for light in lights {
			if !newLights.contains(where: { $0.id == light.id }) {
				newLights.append(light)
			}
		}
		for light in oldLights {
			if !newLights.contains(where: { $0.id == light.id }) {
				newLights.append(light)
			}
		}
		
		if oldLights != newLights {
			for observer in observers {
				observer.lightsDidUpdateHandler(newLights)
			}
			self.lights = newLights
		}
	}
	
	private func selectorToFilter(_ selector: LightTargetSelector) -> LightTargetFilter {
		switch selector.type {
		case .All:
			return { (light) in return true }
		case .ID:
			return { (light) in return light.id == selector.value }
		case .GroupID:
			return { (light) in return light.group?.id == selector.value }
		case .LocationID:
			return { (light) in return light.location?.id == selector.value }
		case .SceneID:
			return { [weak self] (light) in
				if let strongSelf = self, let index = strongSelf.scenes.index(where: { $0.toSelector() == selector }) {
					let scene = strongSelf.scenes[index]
					return scene.states.contains { (state) in
						let filter = strongSelf.selectorToFilter(state.selector)
						return filter(light)
					}
				} else {
					return false
				}
			}
		case .Label:
			return { (light) in return light.label == selector.value }
		}
	}
}

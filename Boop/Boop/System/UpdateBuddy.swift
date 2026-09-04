//
//  UpdateBuddy.swift
//  Boop
//
//  Created by Ivan on 5/30/20.
//  Copyright © 2020 OKatBest. All rights reserved.
//

import Foundation

class UpdateBuddy: NSObject {
    
    @IBOutlet weak var statusView: StatusView!
    
    var firstCheck = true
    
    override init() {
        super.init()
        self.check()
    }
    
    func check() {
    }
    
    private func handleResponse(data: Data) throws {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(VersionContainer.self, from: data)
        
        #if APPSTORE
        
        let latest = payload.mas
        
        #else
        
        let latest = payload.standalone
        
        #endif
        
        guard let thisVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }
        
        if latest.version.compare(thisVersion, options: .numeric) == .orderedDescending {
            self.statusView.setStatus(.updateAvailable(latest.link))
        } else if !firstCheck {
            self.statusView.setStatus(.success("Boop is up to date!"))
        }
        
        self.firstCheck = false
    }
}

//
//  LonaOrganization+url.swift
//  LonaStudio
//
//  Created by Mathieu Dutour on 08/04/2020.
//  Copyright © 2020 Devin Abbott. All rights reserved.
//

import Foundation

let DOCS_BASE_URL = Bundle.main.infoDictionary?["DOCS_BASE_URL"] as! String

extension GetMeQuery.Data.GetMe.Organization {
  var docsURL: URL {
    get {
      URL(string: "\(DOCS_BASE_URL)/\(self.id)")!
    }
  }
}

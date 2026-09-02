//
//  NavigationSelection.swift
//  SigmaStream
//
//  Identifiable wrappers for navigation to detail views.
//

import Foundation

struct MovieSelection: Identifiable, Hashable {
    let id: Int
}

struct TVSeriesSelection: Identifiable, Hashable {
    let id: Int
}

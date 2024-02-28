//
//  Binding.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 29.02.2024.
//

import SwiftUI

prefix func ! (value: Binding<Bool>) -> Binding<Bool> {
    Binding<Bool>(
        get: { !value.wrappedValue },
        set: { value.wrappedValue = !$0 }
    )
}

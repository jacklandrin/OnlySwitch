//
//  SwitchListModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/23.
//

import Foundation

struct SwitchListModel {
    var switchList = [SwitchBarVM]()
    var shortcutsList = [ShortcutsBarVM]()
    
    var maxHeight:CGFloat = 0
    
    var allItemList = Array<BarProvider>() //items which should be shown
    
    var uncategoryItemList = Array<SwitchBarVM>() //for two columns
    
    var audioItemList = Array<SwitchBarVM>() //for two columns
    
    var cleanupItemList = Array<SwitchBarVM>() //for two columns
    
    var toolItemList = Array<SwitchBarVM>() //for two columns

    var evolutionItemList = Array<EvolutionBarVM>()

    var sortMode = false
}

//
//  Core.swift
//  WhichBG
//
//  Created by Utkarsh Upadhyay on 8/2/15.
//  Copyright (c) 2015 Utkarsh Upadhyay. All rights reserved.
//

import Foundation

private let defaultManager = FileManager.default

func isDir(_ path: String) -> Bool {
    var isDir : ObjCBool = false
    let exists = defaultManager.fileExists(atPath: path, isDirectory: &isDir)
    return (exists && isDir.boolValue)
}

func isFile(_ path: String) -> Bool {
    var isDir : ObjCBool = false
    let exists = defaultManager.fileExists(atPath: path, isDirectory: &isDir)
    return (exists && !isDir.boolValue)
}

// Returns all "valid" combinations of folders and files passed to it.
func findAllExistingFilesIn(_ fileFolderList: [String]) ->  [String] {
    var folders : [String] = [], absFiles : [String] = [], relFiles : [String] = [];
    
    let fullFileFolders = fileFolderList.map({ ($0 as NSString).expandingTildeInPath })
    
    for fileFolder in fullFileFolders {
        if isDir(fileFolder) {
            folders.append(fileFolder)
        } else if isFile(fileFolder) {
            absFiles.append(fileFolder)
        } else {
            relFiles.append(fileFolder)
        }
    }
    
    var allFiles = absFiles
    
    for folder in folders {
        for file in relFiles {
            let fileAbsPath = (folder as NSString).appendingPathComponent(file)
            if isFile(fileAbsPath) {
                allFiles.append(fileAbsPath)
            }
        }
    }
    
    return allFiles
}

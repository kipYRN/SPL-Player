      //
//  CustomAssetDownloadDelegate.swift
//  SPLPlayer
//
//  Created by Sean Gray on 12/7/17.
//

import UIKit
import AVKit;
import AVFoundation;

class CustomAssetDownloadDelegate: NSObject, AVAssetDownloadDelegate {
    var downloadPercent: String? = nil;
    var assetDownloadTask:AVAssetDownloadTask? = nil;
    var deleteButton: UIButton? = nil;
    var downloadButton: UIButton? = nil;
    var prepOfflineButton: UIButton? = nil;
    var playButton: UIButton? = nil;
    //get the deleteButton and downloadButton from View so we can update state from download Delegate
    init(deleteButton:UIButton,downloadButton:UIButton,prepOfflineButton: UIButton,playButton: UIButton) {
        self.deleteButton = deleteButton;
        self.downloadButton = downloadButton;
        self.prepOfflineButton = prepOfflineButton;
        self.playButton = playButton;
        super.init()
    }
    
    func setupAssetDownload(target:URL,session:AVAssetDownloadURLSession) {
        let hlsAsset = AVURLAsset(url: target)
        // Download a Movie at 2 mbps
        self.assetDownloadTask = session.makeAssetDownloadTask(asset: hlsAsset, assetTitle: "EZDMTestVideo",
                                                                      assetArtworkData: nil, options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 2000000])!
        self.assetDownloadTask!.resume()
    }
    
    //Cancels the download, note this will call the urlSession DidFinishDownloading method and needs to be handled in there
    func cancel(){
        if let downloadTask = self.assetDownloadTask{
            downloadTask.cancel()
            updateButtons()
        }
    }
    
    func delete(){
        //get the persistent data library
        let userDefaults = UserDefaults.standard
        //check if there is something saved under key savedPath. Should be a bookmark
        if let fileBookmark = userDefaults.data(forKey: "savedPath") {
            let fileManager=FileManager.default
            do {
                var bookmark: Bool = false;
                //attempt to delete the resource found at the path corelating to the found bookmark
                let mediaURL = try URL(resolvingBookmarkData:fileBookmark, bookmarkDataIsStale: &bookmark)
                try fileManager.removeItem(at: mediaURL!)
                //remove the bookmark from the userDefaults library
                userDefaults.removeObject(forKey: "savedPath")
                //update UI
                updateButtons()
            }
            catch {
                print("Failed to Delete File")
            }
        }
    }
    
    //Updates the state of UI based on if and asset is downloaded or not. Envoked on download, deletion and canceling
    func updateButtons(){
        //checks to see if we have a bookmark at key savedPath if so presume we have a downloaded asset
        if UserDefaults.standard.data(forKey:"savedPath") != nil {
            self.downloadButton!.setTitle("Downloaded", for: .normal)
            self.downloadButton!.isEnabled = false
            self.downloadButton!.backgroundColor = UIColor.gray
            self.deleteButton!.isEnabled=true
            self.deleteButton!.backgroundColor = UIColor.red
            if(!self.playButton!.isEnabled){
                self.prepOfflineButton!.isEnabled = true
                self.prepOfflineButton!.backgroundColor = UIColor.green
            }
        }
        // if there is no saved bookmark presume there is no downloaded assets
        else{
            self.downloadButton!.setTitle("Download", for: .normal)
            self.downloadButton!.isEnabled = true
            self.downloadButton!.backgroundColor = UIColor.blue
            self.deleteButton!.isEnabled=false
            self.deleteButton!.backgroundColor = UIColor.gray
            self.prepOfflineButton!.isEnabled = false
            self.prepOfflineButton!.backgroundColor = UIColor.gray
        }
    }
    
    //This function is envoked whenever the AVAssetDownloadTask is compleated Note this includes if the user cancelled
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        //If download percent didnt hit 100% persume user cancelled and we need to clear memory
        if(self.downloadPercent != "100"){
            delete()
        }
        else {
            let userDefaults = UserDefaults.standard
            do {
                //wrike bookmark of location to key savedPath this allows us to acess it later and persistantly
                userDefaults.set(try location.bookmarkData(), forKey:"savedPath")
            }
            catch {
                print("bookmark Error \(error)")
            }
            updateButtons()
        }
    }
    
    //this function is envoked whenever a segment has finished downloading, can be used to monitor status of download
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        // Convert loadedTimeRanges to CMTimeRanges
        var percentComplete = 0.0
        for value in loadedTimeRanges {
            let loadedTimeRange: CMTimeRange = value.timeRangeValue
            percentComplete += CMTimeGetSeconds(loadedTimeRange.duration) /
                CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        }
        percentComplete *= 100
        let stringPercent:String = String(Int(percentComplete))
        self.downloadPercent = stringPercent
        //update download button to show persentages
        self.downloadButton!.setTitle(self.downloadPercent!+"%",for: .normal)
    }
}

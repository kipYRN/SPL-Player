//
//  ViewController.swift
//  SPLPlayer
//
//  Created by Sean Gray on 12/1/17.
//

import UIKit
import AVKit;
import AVFoundation;
import Foundation;

//Server endpoint that points to the key server change number to match AssetID
let KEY_SERVER_URL = "https://fps.ezdrm.com/api/licenses/"
//Location of the manifest for the media you want the app to stream
//let MEDIA_SERVER_ENDPOINT = "https://s3.amazonaws.com/drmsonus/new_son/avancando-com-jenkins/Avancando_com_Jenkins-01-Introducao.mp4/fp/fairplay.m3u8"
//let MEDIA_SERVER_ENDPOINT = "https://fps.ezdrm.com/demo/video/ezdrm.m3u8"

let MEDIA_SERVER_ENDPOINT = "http://52.213.186.230:1080/auth/media/6720586b-1caf-4207-a883-a53641c70e42.ism/.m3u8"


/* ----------------------------
 ** globalNotificationQueue
 
 ** Returns a Dispatch Que for the AVAssetLoader Delegate
 
---------------------------- */

func globalNotificationQueue() -> DispatchQueue {
    
    return DispatchQueue(label: "Stream Queue")
    
}

class ViewController: UIViewController {
    
    var player:AVPlayer? = nil;
    var playerItem:AVPlayerItem? = nil;
    var playerLayer:AVPlayerLayer? = nil;
    var loaderDelegate:CustomAssetLoaderDelegate? = nil;
    var downloadDelegate:CustomAssetDownloadDelegate? = nil;
    var asset: AVURLAsset? = nil;
    var session: AVAssetDownloadURLSession? = nil;
    let PLAYABLE_KEY:String = "playable";
    let STATUS_KEY:String = "status";
    
    
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var downloadButton: UIButton!
    @IBOutlet weak var deleteButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var unloadButton: UIButton!
    @IBOutlet weak var prepOnlineButton: UIButton!
    @IBOutlet weak var prepOfflineButton: UIButton!

    
    private let AVPlayerTestPlaybackViewControllerStatusObservationContext: UnsafeMutableRawPointer? = UnsafeMutableRawPointer.init(mutating:nil);
    
    //Apple presumes that all conections require authorization and a credential space. If we don't define this and register in viewDidLoad then we would get an error saying that the app
    // can't find credentials for the connection. This error dosn't effect anything if using HTTP, but might need to be implemented based on authentication on your media server
    let protectionSpace = URLProtectionSpace.init(host: "licenses.digitalprimates.net",
                                                  port: 80,
                                                  protocol: "http",
                                                  realm: nil,
                                                  authenticationMethod: nil)
    let userCredential = URLCredential(user: "",
                                       password: "",
                                       persistence: .permanent)
    
    func setEnabled(button: UIButton){
        button.isEnabled = true;
        button.backgroundColor = UIColor.green;
    }
    func setDisabled(button: UIButton){
        button.isEnabled = false;
        button.backgroundColor = UIColor.gray;
    }
    
    /* ------------------------------------------
    ** observeValue:
    **
    **    Called when the value at the specified key path relative
     **  to the given object has changed.
    **  Start movie playback when the AVPlayerItem is ready to
    **  play.
    **  Report and error if the AVPlayerItem cannot be played.
    **
    **  NOTE: this method is invoked on the main queue.
    ** ------------------------------------------------------- */
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        //make sure the
        if context == AVPlayerTestPlaybackViewControllerStatusObservationContext {
            let status = AVPlayerItemStatus(rawValue: change![.newKey] as! Int)
            
            switch status! {
                case .unknown:
                    break
                case .readyToPlay:
                    if self.player != nil {
                        setEnabled(button: self.playButton)
                    }
                    break
                case .failed:
                    let playerItem = object as? AVPlayerItem
                    assetFailedToPrepare(error:playerItem?.error)
                }
        }
        else{
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    /*
     assetFailedToPrepare:
    
     if the AVPlayer state returns failed,
     assetFailedToPrepare will output the error in a alert box
    */
    func assetFailedToPrepare(error:Error?){
        /* Display the error. */
        if self.loaderDelegate is CustomAssetDownloadLoaderDelegate {
            if let errorWCode = error as NSError? {
                self.loaderDelegate!.removeKey(fileManager: FileManager.default)
                if Reachability.isConnectedToNetwork() == true && errorWCode.code == -11800{
                    print("Rerequesting Key")
                    self.initOfflineURLAsset(urlString: MEDIA_SERVER_ENDPOINT)
                    self.readyMediaStream()
                    return;
                }
            }
        }
        let alert = UIAlertController(title: error?.localizedDescription, message: (error as NSError?)?.localizedFailureReason, preferredStyle: .alert)
        let defaultAction = UIAlertAction(title: "OK", style: .default, handler: {(_ action: UIAlertAction) -> Void in
        })
        alert.addAction(defaultAction)
        present(alert, animated: true, completion: nil)
        self.unload(self);
    }
    
    /* --------------------------------------------------------------
     **
     **  prepareToPlayAsset:withKeys
     **
     **  Invoked at the completion of the loading of the values for all
     **  keys on the asset that we require. Checks whether loading was
     **  successfull and whether the asset is playable. If so, sets up
     **  an AVPlayerItem and an AVPlayer to play the asset.
     **
     ** ----------------------------------------------------------- */
    
    func prepareToPlayAsset(asset: AVURLAsset,requestedKeys:Array<String>){
        
        // if we are already have an AVPlayer Item stop listening to it
        if(self.playerItem != nil){
            self.playerItem?.removeObserver(self, forKeyPath: STATUS_KEY)
        }
        // Create a new AVPlayerItem with the given AVURLAsset
        self.playerItem = AVPlayerItem(asset: asset)
        
        //If we don't have a AVPlayer already Create a new player with the new AVPlayerItem
         if (self.player == nil){
            self.player = AVPlayer(playerItem: self.playerItem);
            self.playerLayer = AVPlayerLayer(player:self.player);
            self.playerLayer!.frame = self.view.bounds;
            self.view.layer.addSublayer(self.playerLayer!)
            self.player!.usesExternalPlaybackWhileExternalScreenIsActive = true;
         }
       
        NotificationCenter.default.addObserver(self, selector: #selector(self.playerDidFinishPlaying(note:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.playerItem)
        
        
        // Add an Observer to the new AVPlayerItem to listen to the Status Key for when it is ready to play
        self.playerItem?.addObserver(self, forKeyPath: STATUS_KEY, options: [.initial, .new], context: nil)
        //If we have a player not playing the new playerItem replace the current item with the new playerItem
        if(self.player?.currentItem != self.playerItem){
            self.player?.replaceCurrentItem(with: self.playerItem)
        }
    }
    
    
    @objc func playerDidFinishPlaying(note:Any){
        print("done")
        if(self.player != nil) {
            self.player?.pause()
            self.playerLayer?.removeFromSuperlayer()
            self.player = nil;
            self.playerLayer = nil;
        }
    }
    
    /* -----------------------------------------
    ** initURLAsset
    **
    ** creates the AVURLAseet to use for playback if one has not been already created
    ** since we only have one stream we can presume the asset will always be the same
    ** so by checking we can save memory and prevent state issues due to configuration
    ** on the asset changing
    ** ----------------------------------------*/
    
    func initOnlineURLAsset(urlString:String){
            let urlStr: String = urlString;
            var url:URL? = nil;
            url = URL(string: urlStr)
            //set AssetLoaderDelegate to version that dosn't set keys
            self.loaderDelegate = CustomAssetLoaderDelegate();
            self.asset = AVURLAsset(url: url!);
            self.asset!.resourceLoader.setDelegate(self.loaderDelegate, queue: globalNotificationQueue());
    }
    
    /* -----------------------------------------
     ** initURLAsset
     **
     ** creates the AVURLAseet to use for playback if one has not been already created
     ** since we only have one stream we can presume the asset will always be the same
     ** so by checking we can save memory and prevent state issues due to configuration
     ** on the asset changing
     ** ----------------------------------------*/
    
    func initOfflineURLAsset(urlString:String){
        
        print("We here")
        var url:URL? = nil;
        let userDefaults = UserDefaults.standard
        var bookmarkDataIsStale = false;
        //Check if there is a saved download if true use that insead of path
        if let fileBookmark = userDefaults.data(forKey:"savedPath") {
            print("Using Local File")
            do {
                url = try URL(resolvingBookmarkData:fileBookmark, bookmarkDataIsStale: &bookmarkDataIsStale)
            }
            catch {
                print ("URL from Bookmark Error: \(error)")
            }
            //set AssetLoaderDelegate to version with persistant keys
            self.loaderDelegate = CustomAssetDownloadLoaderDelegate()
            self.asset = AVURLAsset(url: url!);
            self.asset!.resourceLoader.setDelegate(self.loaderDelegate, queue: globalNotificationQueue());
        }
        else {
            print("no local file")
        }
    }
    /* -----------------------------------------
     ** initURLAssetForDownload
     **
     ** creates the AVURLAseet to use for playback that is set up to store persistant keys
     ** this allows for the preloading for offline HLS
     ** ----------------------------------------*/
    
    func initURLAssetForDownload(url:URL){
        self.asset = AVURLAsset(url: url);
        //set AssetLoaderDelegate to version that can save keys
        self.loaderDelegate = CustomAssetDownloadLoaderDelegate()
        //Imediatly request keys instead of waiting for playback, this allows for saving keys
        self.asset!.resourceLoader.preloadsEligibleContentKeys = true
        self.asset!.resourceLoader.setDelegate(self.loaderDelegate, queue: globalNotificationQueue());
    }
    
    /* -----------------------------------------
     ** playMediaStream
     **
     ** checks for if the asset is loaded and playable
     ** if so it starts playback if not it throws error
     ** ----------------------------------------*/
    //attempts to create a new AVURLAsset then checks fow when the asset is loaded to start the playback initialization.
    
    func readyMediaStream(){
        let requestedKeys:Array<String> = [PLAYABLE_KEY];
        //load the value of playable and execute code block with result
        if let asset = self.asset {
            asset.loadValuesAsynchronously(forKeys: requestedKeys, completionHandler: ({
                () -> Void in
                var error: NSError? = nil
                switch self.asset!.statusOfValue(forKey: self.PLAYABLE_KEY, error: &error){
                case .loaded:
                    if(self.asset!.isPlayable){
                        self.initPlay(asset:self.asset!,keys:requestedKeys)
                    }
                    else {
                        print("Not Playable")
                    }
                case .failed:
                    print("No Playable Status")
                case .cancelled:
                    print("Loading Cancelled")
                default:
                    print("loading error Unknown")
                }
            }))
        }
    }
    
    //makes the asset preperation calls Async so other actions can occur at the same time
    func initPlay(asset: AVURLAsset, keys: Array<String>){
        DispatchQueue.main.async(execute: {() -> Void in
            /* IMPORTANT: Must dispatch to main queue in order to operate on the AVPlayer and AVPlayerItem. */
            self.prepareToPlayAsset(asset:asset, requestedKeys: keys)
        })
    }
    
    //Initializes new AVURLAsset, initializes a new downloadDelegate if it dosn't exist then starts a download using the downloadDelegate
    func downloadMediaStream(){
        
    }
    
    //Called when play button is released, trys to play media at the media server endpoint
    @IBAction func play(_ sender: UIButton) {
        self.player?.play()
    }
    
    @IBAction func prepOffline(_ sender: Any) {
        //make sure we don't have anything already loaded before loading new resource
        if(self.player == nil){
            setDisabled(button: prepOnlineButton)
            setDisabled(button: deleteButton)
            initOfflineURLAsset(urlString: MEDIA_SERVER_ENDPOINT)
            readyMediaStream()
        }
        else {
            print("has asset")
        }
    }
    @IBAction func prepOnline(_ sender: Any) {
        //make sure we don't have anything already loaded before loading new resource
        if(self.player == nil){
            setDisabled(button: prepOfflineButton)
            initOnlineURLAsset(urlString: MEDIA_SERVER_ENDPOINT)
            readyMediaStream()
        }
        else {
            print("does has asset")
        }
    }
    
    //Called when Stop button is released, if media is playing it stops the feed and then dealocates the player
    @IBAction func pause(_ sender: Any) {
        print("Stop")
        if(self.player != nil) {
            self.player?.pause()
        }
    }
    
    @IBAction func unload(_ sender: Any) {
        setDisabled(button: playButton)
        setEnabled(button: prepOnlineButton)
        if(!downloadButton.isEnabled){
            setEnabled(button: prepOfflineButton)
            deleteButton.isEnabled = true;
            deleteButton.backgroundColor = UIColor.red;
        }
        self.player?.pause()
        self.playerLayer?.removeFromSuperlayer()
        self.player = nil;
        self.asset = nil;
        self.playerLayer = nil;
    }

    //Called when Download Button is released starts download of media at the media server endpoint
    @IBAction func download(_ sender: Any) {
        print("download")
        //disable button so we don't end up downloading 2 things
        setDisabled(button: downloadButton)
        let url = URL(string:MEDIA_SERVER_ENDPOINT)
        initURLAssetForDownload(url: url!)
        self.downloadDelegate!.setupAssetDownload(target:url!,session:self.session!)
    }
    
    //Called when Delete Button is released checks for a download existing and if so deleates the download
    @IBAction func deleteDownload(_ sender: Any) {
        print("deleting")
        //clear asset references
        self.asset = nil
        if let download = self.downloadDelegate {
            self.loaderDelegate?.removeKey(fileManager: FileManager.default)
            download.delete()
        }
    }
    
    //Called when Cancel Button is released checks for a download existing and if so cancels the download
    @IBAction func cancel(_ sender: Any) {
        print("cancel")
        if let download = self.downloadDelegate {
            download.cancel()
        }
        else{
            print("No Download Taking Place")
        }
    }

    //set initial state for when the view has loaded
    override func viewDidLoad() {
        URLCredentialStorage.shared.setDefaultCredential(userCredential, for: protectionSpace)
        //creating the AVAssetDownloadURLSession to control the background downloading, is singleton to make sure only one thing downloads at a time
        setDisabled(button: playButton)
        let config = URLSessionConfiguration.background(withIdentifier:"assetDownloadConfigurationIdentifier")
        self.downloadDelegate = CustomAssetDownloadDelegate(deleteButton: deleteButton,downloadButton: downloadButton,prepOfflineButton: prepOfflineButton,playButton: playButton)
        self.downloadDelegate?.updateButtons()
        self.session = AVAssetDownloadURLSession(
            configuration: config,
            assetDownloadDelegate: self.downloadDelegate,
            delegateQueue: OperationQueue.main)
        //check if there are any currently running download tasks, and if so resume them
        session!.getAllTasks { tasks in
            for task in tasks {
                if let assetDownloadTask = task as? AVAssetDownloadTask {
                    assetDownloadTask.resume()
                } }
        }
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}


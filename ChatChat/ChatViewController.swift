/*
 * Copyright (c) 2015 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import Photos
import Firebase
import JSQMessagesViewController
import MobileCoreServices

final class ChatViewController: JSQMessagesViewController {
    
    // MARK: Properties
    private let imageURLNotSetKey = "NOTSET"
    var mysenderDisplayName: String = ""
    
    var channelRef: FIRDatabaseReference?
    
    private lazy var messageRef: FIRDatabaseReference = self.channelRef!.child("messages")
    fileprivate lazy var storageRef: FIRStorageReference = FIRStorage.storage().reference(forURL: "gs://mytestapp-b880d.appspot.com")
    
    private lazy var userIsTypingRef: FIRDatabaseReference = self.channelRef!.child("typingIndicator").child(self.senderId())
    private lazy var usersTypingQuery: FIRDatabaseQuery = self.channelRef!.child("typingIndicator").queryOrderedByValue().queryEqual(toValue: true)
    
    private var newMessageRefHandle: FIRDatabaseHandle?
    private var updatedMessageRefHandle: FIRDatabaseHandle?
    
    private var messages: [JSQMessage] = []
    private var photoMessageMap = [String: JSQPhotoMediaItem]()
    private var audioMessageMap = [String: JSQAudioMediaItem]()
    
    private var localTyping = false
    
    private var timer: Timer?
    private var timerStop: Bool = false
    private var tickCount : Int = 0
    
    var channel: Channel? {
        didSet {
            title = channel?.name
        }
    }
    
    var isTyping: Bool {
        get {
            return localTyping
        }
        set {
            localTyping = newValue
            userIsTypingRef.setValue(newValue)
        }
    }
    
    lazy var outgoingBubbleImageView: JSQMessagesBubbleImage = self.setupOutgoingBubble()
    lazy var incomingBubbleImageView: JSQMessagesBubbleImage = self.setupIncomingBubble()
    
    var avatars = Dictionary<String, UIImage>()
    
    // MARK: View Lifecycle
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        AudioBot.prepareForNormalRecord()
        
        //self.senderId = FIRAuth.auth()?.currentUser?.uid
        observeMessages()
        let img = UIImage(named: "send_icn")
        self.inputToolbar.contentView?.rightBarButtonItem?.setTitle("", for: UIControlState.normal)
        self.inputToolbar.contentView?.rightBarButtonItem?.setImage(img, for: UIControlState.normal)
        
        let height = self.inputToolbar.contentView?.leftBarButtonContainerView?.frame.size.height
        let recordImg = UIImage(named: "record")
        let recordBtn = UIButton(type: .custom)
        recordBtn.setImage(recordImg, for: .normal)
        recordBtn.frame = CGRect(x: 0, y: 0, width: 25, height: height!)
        recordBtn.addTarget(self, action: #selector(didPressRecordButton(_ :)), for: .touchUpInside)
        
        let attachImg = UIImage(named: "clip")
        let attachBtn = UIButton(type: .custom)
        attachBtn.setImage(attachImg, for: .normal)
        attachBtn.frame = CGRect(x: 30, y: 0, width: 25, height: height!)
        attachBtn.addTarget(self, action: #selector(didPressAccessoryButton(_ :)), for: .touchUpInside)
        
        self.inputToolbar.contentView?.leftBarButtonItemWidth = 55;
        self.inputToolbar.contentView?.rightBarButtonItemWidth = 30;
        
        self.inputToolbar.contentView?.leftBarButtonContainerView?.addSubview(recordBtn)
        self.inputToolbar.contentView?.leftBarButtonContainerView?.addSubview(attachBtn)
        
        self.inputToolbar.contentView?.leftBarButtonItem?.isHidden = true;
        
        collectionView?.collectionViewLayout.springinessEnabled = false
        
        automaticallyScrollsToMostRecentMessage = true
        // No avatars
        //collectionView!.collectionViewLayout.incomingAvatarViewSize = CGSize.zero
        //collectionView!.collectionViewLayout.outgoingAvatarViewSize = CGSize.zero
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        observeTyping()
    }
    
    deinit {
        if let refHandle = newMessageRefHandle {
            messageRef.removeObserver(withHandle: refHandle)
        }
        if let refHandle = updatedMessageRefHandle {
            messageRef.removeObserver(withHandle: refHandle)
        }
    }
    
    // MARK: Collection view data source (and related) methods
    
    override func senderId() -> String {
        return (FIRAuth.auth()?.currentUser?.uid)!
    }
    
    override func senderDisplayName() -> String {
        return self.mysenderDisplayName
    }
    override func collectionView(_ collectionView: JSQMessagesCollectionView, messageDataForItemAt indexPath: IndexPath) -> JSQMessageData {
        return messages[indexPath.item]
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages.count
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView, messageBubbleImageDataForItemAt indexPath: IndexPath) -> JSQMessageBubbleImageDataSource? {
        let message = messages[indexPath.item] // 1
        if message.senderId == self.senderId() { // 2
            return outgoingBubbleImageView
        } else { // 3
            return incomingBubbleImageView
        }
    }
    
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAt: indexPath) as! JSQMessagesCollectionViewCell
        
        let message = messages[indexPath.item]
        
        if message.senderId == self.senderId() { // 1
            cell.textView?.textColor = UIColor.white // 2
        } else {
            cell.textView?.textColor = UIColor.black // 3
        }
        
        return cell
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView, avatarImageDataForItemAt indexPath: IndexPath) -> JSQMessageAvatarImageDataSource? {
        let message = messages[indexPath.item]
        let rgbValue = message.senderId.hash
        let r = CGFloat(Float((rgbValue & 0xFF0000) >> 16)/255.0)
        let g = CGFloat(Float((rgbValue & 0xFF00) >> 8)/255.0)
        let b = CGFloat(Float(rgbValue & 0xFF)/255.0)
        let color = UIColor(red: r, green: g, blue: b, alpha: 0.5)
        let senderDisplayName = message.senderDisplayName
        
        let nameLength = senderDisplayName.characters.count
        let index = senderDisplayName.index(senderDisplayName.startIndex, offsetBy: min(3, nameLength))
        let initials = senderDisplayName.substring(to: index).uppercased()
        let userImage = JSQMessagesAvatarImageFactory().avatarImage(withUserInitials: initials, backgroundColor: color, textColor: UIColor.white, font: UIFont.systemFont(ofSize: 13))
        return userImage
        //return nil
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView, layout collectionViewLayout: JSQMessagesCollectionViewFlowLayout, heightForMessageBubbleTopLabelAt indexPath: IndexPath) -> CGFloat {
        return 15
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView?, attributedTextForMessageBubbleTopLabelAt indexPath: IndexPath) -> NSAttributedString? {
        let message = messages[indexPath.item]
        switch message.senderId {
        case self.senderId():
            return nil
        default:
            let senderDisplayName = message.senderDisplayName
            return NSAttributedString(string: senderDisplayName)
        }
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView, didTapMessageBubbleAt indexPath: IndexPath) {
        let message = messages[indexPath.item]
        if message.isMediaMessage {
            let media = message.media as! JSQMediaItem
            if media is JSQPhotoMediaItem {
                let imgItem = media as! JSQPhotoMediaItem
                let picView = PictureView(imgItem.image)
                self.present(picView!, animated: true, completion: nil)
            }
        }
        
    
    }
    
    
    // MARK: Firebase related methods
    
    private func observeMessages() {
        messageRef = channelRef!.child("messages")
        let messageQuery = messageRef.queryLimited(toLast:25)
        
        // We can use the observe method to listen for new
        // messages being written to the Firebase DB
        newMessageRefHandle = messageQuery.observe(.childAdded, with: { (snapshot) -> Void in
            let messageData = snapshot.value as! Dictionary<String, String>
            
            if let id = messageData["senderId"] as String!, let name = messageData["senderName"] as String!, let text = messageData["text"] as String!, text.characters.count > 0 {
                self.addMessage(withId: id, name: name, text: text)
                self.finishReceivingMessage()
            } else if let id = messageData["senderId"] as String!, let mediaType = messageData["mediaType"] as String! , let remoteURL =  messageData["remoteURL"] as String! {
                let localURL = messageData["localURL"] as String!
                
                if mediaType == "photo" {
                    let mediaItem = JSQPhotoMediaItem(maskAsOutgoing: id == self.senderId())
                    self.addPhotoMessage(withId: id, name: messageData["senderName"] ?? "", key: snapshot.key, mediaItem: mediaItem)
                    
                    if remoteURL.hasPrefix("gs://") {
                        self.fetchImageDataAtURL(remoteURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: nil)
                    }
                }
                
                else if mediaType == "audio" {
                    
                    //                    let audioData = try? Data(contentsOf: newFileURL)
                    //                    let audioItem = JSQAudioMediaItem(data: audioData)
                    //                    let audioMessage = JSQMessage(senderId: (self?.senderId())!, displayName: (self?.senderDisplayName())!, media: audioItem)
                    //                    self?.messages.append(audioMessage)
                    //                    self?.finishSendingMessage(animated: true)
                    
                    //let audioData : Data? = nil
                    
                    let mediaItem = JSQAudioMediaItem(data: nil)//JSQAudioMediaItem(maskAsOutgoing: id == self.senderId())
                    mediaItem.appliesMediaViewMaskAsOutgoing = (id == self.senderId())
                    self.addAudioMessage(withId: id, name: messageData["senderName"] ?? "", key: snapshot.key, mediaItem: mediaItem)
                    
                    if remoteURL.hasPrefix("gs://") {
                        self.fetchAudioDataAtURL(remoteURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: nil)
                    }
                }
                
            } else {
                print("Error! Could not decode message data")
            }
        })
        
        // We can also use the observer method to listen for
        // changes to existing messages.
        // We use this to be notified when a photo has been stored
        // to the Firebase Storage, so we can update the message data
        updatedMessageRefHandle = messageRef.observe(.childChanged, with: { (snapshot) in
            let key = snapshot.key
            let messageData = snapshot.value as! Dictionary<String, String>
            
            if let mediaType = messageData["mediaType"] as String! , let remoteURL =  messageData["remoteURL"] as String! {
                if mediaType == "photo" {
                    let localURL = messageData["localURL"] as String!
                    
                    // The photo has been updated.
                    if let mediaItem = self.photoMessageMap[key] {
                        self.fetchImageDataAtURL(remoteURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: key)
                    }
                }
                
                else if mediaType == "audio" {
                    // The photo has been updated.
                    if let mediaItem = self.audioMessageMap[key] {
                        self.fetchAudioDataAtURL(remoteURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: key)
                    }
                }
                
            }
            
        })
    }
    
    private func fetchImageDataAtURL(_ photoURL: String,  forMediaItem mediaItem: JSQPhotoMediaItem, clearsPhotoMessageMapOnSuccessForKey key: String?) {
        let storageRef = FIRStorage.storage().reference(forURL: photoURL)
        storageRef.data(withMaxSize: INT64_MAX){ (data, error) in
            if let error = error {
                print("Error downloading image data: \(error)")
                return
            }
            
            storageRef.metadata(completion: { (metadata, metadataErr) in
                if let error = metadataErr {
                    print("Error downloading metadata: \(error)")
                    return
                }
                
                if (metadata?.contentType == "image/gif") {
                    mediaItem.image = UIImage.gifWithData(data!)
                } else {
                    mediaItem.image = UIImage.init(data: data!)
                    
                }
                
                self.collectionView?.reloadData()
                
                guard key != nil else {
                    _ = appAlbum.save(image: mediaItem.image!, isRemote: false)
                    return
                }
                self.photoMessageMap.removeValue(forKey: key!)
            })
        }
    }
    
    private func fetchAudioDataAtURL(_ photoURL: String, forMediaItem mediaItem: JSQAudioMediaItem, clearsPhotoMessageMapOnSuccessForKey key: String?) {
        let storageRef = FIRStorage.storage().reference(forURL: photoURL)
        storageRef.data(withMaxSize: INT64_MAX){ (data, error) in
            if let error = error {
                print("Error downloading image data: \(error)")
                return
            }
            
            storageRef.metadata(completion: { (metadata, metadataErr) in
                if let error = metadataErr {
                    print("Error downloading metadata: \(error)")
                    return
                }
                
                mediaItem.audioData = data
                
                self.collectionView?.reloadData()
                
                guard key != nil else {
                    return
                }
                self.audioMessageMap.removeValue(forKey: key!)
            })
        }
    }
    
    private func observeTyping() {
        let typingIndicatorRef = channelRef!.child("typingIndicator")
        userIsTypingRef = typingIndicatorRef.child(senderId())
        userIsTypingRef.onDisconnectRemoveValue()
        usersTypingQuery = typingIndicatorRef.queryOrderedByValue().queryEqual(toValue: true)
        
        usersTypingQuery.observe(.value) { (data: FIRDataSnapshot) in
            
            // You're the only typing, don't show the indicator
            if data.childrenCount == 1 && self.isTyping {
                return
            }
            
            // Are there others typing?
            self.showTypingIndicator = data.childrenCount > 0
            self.scrollToBottom(animated: true)
        }
    }
    
    override func didPressSend(_ button: UIButton, withMessageText text: String, senderId: String, senderDisplayName: String, date: Date) {
        // 1
        let itemRef = messageRef.childByAutoId()
        
        // 2
        let messageItem = [
            "senderId": senderId,
            "senderName": senderDisplayName,
            "text": text,
            ]
        
        // 3
        itemRef.setValue(messageItem)
        
        // 4
        //JSQSystemSoundPlayer.jsq_playMessageSentSound()
        
        // 5
        finishSendingMessage()
        isTyping = false
    }
    
    func sendPhotoMessage() -> String? {
        let itemRef = messageRef.childByAutoId()
        
        let messageItem = [
            "photoURL": imageURLNotSetKey,
            "senderId": senderId(),
            ]
        
        itemRef.setValue(messageItem)
        
        //JSQSystemSoundPlayer.jsq_playMessageSentSound()
        
        finishSendingMessage()
        return itemRef.key
    }
    
    func sendMediaMessage(_ localURL: String, _ mediaType: String) -> String? {
        let itemRef = messageRef.childByAutoId()
        
        let messageItem = [
            "senderId": senderId(),
            "senderName": senderDisplayName(),
            "mediaType": mediaType,
            "remoteURL": imageURLNotSetKey,
            "localURL": localURL
        ]
        
        itemRef.setValue(messageItem)
        
        //JSQSystemSoundPlayer.jsq_playMessageSentSound()
        
        finishSendingMessage()
        return itemRef.key
    }
    
    func setRemoteMediaURL(_ url: String, forMediaMessageWithKey key: String) {
        let itemRef = messageRef.child(key)
        itemRef.updateChildValues(["remoteURL": url])
    }
    
    func setImageURL(_ url: String, forPhotoMessageWithKey key: String) {
        let itemRef = messageRef.child(key)
        itemRef.updateChildValues(["photoURL": url])
    }
    
    // MARK: UI and User Interaction
    
    private func setupOutgoingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory.outgoingMessagesBubbleImage(with: UIColor.jsq_messageBubbleBlue())
    }
    
    private func setupIncomingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory.incomingMessagesBubbleImage(with: UIColor.jsq_messageBubbleLightGray())
    }
    
    func didPressRecordButton(_ sender: UIButton){
        
        self.timerStop = false;
        self.inputToolbar.contentView!.textView!.resignFirstResponder()
        let sheet = UIAlertController(title: "Recording ... 0s", message: nil, preferredStyle: .actionSheet)
        
        let customTitle:NSString = "Recording ... 0s" // Use NSString, which lets you call rangeOfString()
        let systemBoldAttributes:[String : AnyObject] = [
            // setting the attributed title wipes out the default bold font,
            // so we need to reconstruct it.
            NSFontAttributeName : UIFont.boldSystemFont(ofSize: 17),
            NSForegroundColorAttributeName : UIColor.red
        ]
        let attributedString = NSMutableAttributedString(string: customTitle as String, attributes:systemBoldAttributes)
        sheet.setValue(attributedString, forKey: "attributedTitle")

        let sendAction = UIAlertAction(title: "Send" , style: .default) { (action) in
            print("File Sent...")
            self.timerStop = true;
            if AudioBot.recording {
                AudioBot.stopRecord { [weak self] fileURL, duration, decibelSamples in
                    print("fileURL: \(fileURL)")
                    print("duration: \(duration)")
                    //print("decibelSamples: \(decibelSamples)")
                    guard let newFileURL = FileManager.voicememo_audioFileURLWithName(UUID().uuidString, "m4a") else { return }
                    guard let _ = try? FileManager.default.copyItem(at: fileURL, to: newFileURL) else { return }
                    let _ = try? FileManager.default.removeItem(at: fileURL)
                    
//                    let audioData = try? Data(contentsOf: newFileURL)
//                    let audioItem = JSQAudioMediaItem(data: audioData)
//                    let audioMessage = JSQMessage(senderId: (self?.senderId())!, displayName: (self?.senderDisplayName())!, media: audioItem)
//                    self?.messages.append(audioMessage)
//                    self?.finishSendingMessage(animated: true)
                    
                    if let key = self?.sendMediaMessage(newFileURL.absoluteString, "audio") {
                        let path = "\(String(describing: FIRAuth.auth()?.currentUser?.uid))/\(Int(Date.timeIntervalSinceReferenceDate * 1000))/memo.m4a"
                        self?.storageRef.child(path).putFile(newFileURL, metadata: nil) { (metadata, error) in
                            if let error = error {
                                print("Error uploading photo: \(error.localizedDescription)")
                                return
                            }
                            self?.setRemoteMediaURL((self?.storageRef.child((metadata?.path)!).description)!, forMediaMessageWithKey: key)
                        }
                    }
                    
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) {
            (action) in
            self.timerStop = true;
            if AudioBot.recording {
                AudioBot.stopRecord { fileURL, duration, decibelSamples in
                    print("fileURL: \(fileURL)")
                    print("duration: \(duration)")
                    guard let _ = try? FileManager.default.removeItem(at: fileURL) else { return }
                    
                }
            }
        }
        
        sheet.addAction(sendAction)
        sheet.addAction(cancelAction)
        
        do {
            let decibelSamplePeriodicReport: AudioBot.PeriodicReport = (reportingFrequency: 10, report: { decibelSample in
                //print("decibelSample: \(decibelSample)")
            })
            AudioBot.mixWithOthersWhenRecording = true
            try AudioBot.startRecordAudio(forUsage: .normal, withDecibelSamplePeriodicReport: decibelSamplePeriodicReport)
        } catch {
            print("record error: \(error)")
            return
        }
        
        self.present(sheet, animated: true){
            self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.countDownTimer), userInfo: nil, repeats: true)
        }
    }
    
    func countDownTimer() {
        
        //let okAction = alertController.actions.first
        
        if timerStop {
            timer?.invalidate()
            timer = nil
            tickCount = 0;
        } else {
            tickCount += 1 ;
            if let alertController = self.presentedViewController as? UIAlertController {
                //alertController.setValue("Recording ... \(tickCount)s", forKey: "title")
                
                let customTitle = "Recording ... \(tickCount)s"
                let systemBoldAttributes:[String : AnyObject] = [
                    // setting the attributed title wipes out the default bold font,
                    // so we need to reconstruct it.
                    NSFontAttributeName : UIFont.boldSystemFont(ofSize: 17),
                    NSForegroundColorAttributeName : UIColor.red
                ]
                let attributedString = NSMutableAttributedString(string: customTitle as String, attributes:systemBoldAttributes)
                
                alertController.setValue(attributedString, forKey: "attributedTitle")
            }
        }
    }
    
    override func didPressAccessoryButton(_ sender: UIButton) {
        
        self.inputToolbar.contentView!.textView!.resignFirstResponder()
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        let cameraAction = UIAlertAction(title: "Camera" , style: .default) { (action) in
            let picker = UIImagePickerController()
            picker.delegate = self
            if (UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera)) {
                picker.sourceType = UIImagePickerControllerSourceType.camera
            } else {
                picker.sourceType = UIImagePickerControllerSourceType.photoLibrary
            }
            self.present(picker, animated: true, completion:nil)
        }
        
        let photoAction = UIAlertAction(title: "Photo & Video Library", style: .default) { (action) in
            let picker = UIImagePickerController()
            picker.delegate = self
            picker.sourceType = UIImagePickerControllerSourceType.photoLibrary
            self.present(picker, animated: true, completion:nil)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        sheet.addAction(cameraAction)
        sheet.addAction(photoAction)
        sheet.addAction(cancelAction)
        
        self.present(sheet, animated: true, completion: nil)
    }
    
    private func addMessage(withId id: String, name: String, text: String) {
        let message = JSQMessage(senderId: id, displayName: name, text: text)
        messages.append(message)
        
    }
    
    private func addPhotoMessage(withId id: String, name: String, key: String, mediaItem: JSQPhotoMediaItem) {
        let message = JSQMessage(senderId: id, displayName: name, media: mediaItem)
        messages.append(message)
        
        if (mediaItem.image == nil) {
            photoMessageMap[key] = mediaItem
        }
        
        collectionView?.reloadData()
        
    }
    
    private func addAudioMessage(withId id: String, name: String, key: String, mediaItem: JSQAudioMediaItem) {
        let message = JSQMessage(senderId: id, displayName: name, media: mediaItem)
        messages.append(message)
        self.finishSendingMessage(animated: true)
        if (mediaItem.audioData == nil) {
            audioMessageMap[key] = mediaItem
        }
        
        collectionView?.reloadData()
        
    }
    
    // MARK: UITextViewDelegate methods
    
    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)
        // If the text is not empty, the user is typing
        isTyping = textView.text != ""
    }
    
}

// MARK: Image Picker Delegate
extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        
        picker.dismiss(animated: true, completion:nil)
        if let photoReferenceUrl = info[UIImagePickerControllerReferenceURL] as? URL {
            
            // Handle picking a Photo from the Photo Library
            let assets = PHAsset.fetchAssets(withALAssetURLs: [photoReferenceUrl], options: nil)
            let asset = assets.firstObject
            
            if let key = sendMediaMessage(photoReferenceUrl.absoluteString, "photo") {
                
                let assetResrc = PHAssetResource.assetResources(for: asset!).first
                let option = PHAssetResourceRequestOptions()
                option.isNetworkAccessAllowed = true
                
                let docDir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                var name = NSDate().timeIntervalSince1970.description
                
                name = "\(name)_came.JPG"
                
                let imageURL = docDir.appendingPathComponent(name)
                
                PHAssetResourceManager.default().writeData(for: assetResrc!, toFile: imageURL, options: option, completionHandler: {error in
                })
                let path = "\(String(describing: FIRAuth.auth()?.currentUser?.uid))/\(Int(Date.timeIntervalSinceReferenceDate * 1000))/\(photoReferenceUrl.lastPathComponent)"
                self.storageRef.child(path).putFile(imageURL, metadata: nil) { (metadata, error) in
                    if let error = error {
                        print("Error uploading photo: \(error.localizedDescription)")
                        return
                    }
                    self.setRemoteMediaURL(self.storageRef.child((metadata?.path)!).description, forMediaMessageWithKey: key)
                }
            }
        } else {
            // Handle picking a Photo from the Camera - TODO
            if let img = info[UIImagePickerControllerOriginalImage] as? UIImage {
                if let imageFileURLStr = appAlbum.save(image: img, isRemote: false){
                    let imageFileURL = URL(string: imageFileURLStr)
                    
                    if let key = sendMediaMessage(imageFileURLStr, "photo") {
                        let path = "\(String(describing: FIRAuth.auth()?.currentUser?.uid))/\(Int(Date.timeIntervalSinceReferenceDate * 1000))/asset.JPG"
                        
                        self.storageRef.child(path).putFile(imageFileURL!, metadata: nil) { (metadata, error) in
                            if let error = error {
                                print("Error uploading photo: \(error.localizedDescription)")
                                return
                            }
                            self.setRemoteMediaURL(self.storageRef.child((metadata?.path)!).description, forMediaMessageWithKey: key)
                        }
                    }
                }
            }
        }
    }
    
    fileprivate func createDir(dirName: String) {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dataPath = documentsDirectory.appendingPathComponent(dirName)
        
        do {
            try FileManager.default.createDirectory(atPath: dataPath.absoluteString, withIntermediateDirectories: false, attributes: nil)
        } catch _ as NSError {
            //printError("Error creating directory: \(error.localizedDescription)")
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion:nil)
    }
    
    func getAtributedMsg(text: String) -> NSMutableAttributedString {
        if #available(iOS 8.0, *) {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = NSTextAlignment.left
            
            let messageText = NSMutableAttributedString(
                string: text,
                attributes: [
                    NSParagraphStyleAttributeName: paragraphStyle,
                    ]
            )
            return messageText
        }
        else {
            let messageText = NSMutableAttributedString(
                string: text
            )
            return messageText
        }
        
    }
    
}

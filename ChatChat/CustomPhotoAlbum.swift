import Foundation
import Photos

let appAlbum: CustomPhotoAlbum = CustomPhotoAlbum();

class CustomPhotoAlbum: NSObject {
    static let albumName = "IRCAlbum"
    static let sharedInstance = CustomPhotoAlbum()
    
    var assetCollection: PHAssetCollection!
    
    override init() {
        super.init()
        
        if let assetCollection = fetchAssetCollectionForAlbum() {
            self.assetCollection = assetCollection
            return
        }
        
        if PHPhotoLibrary.authorizationStatus() != PHAuthorizationStatus.authorized {
            PHPhotoLibrary.requestAuthorization({ (status: PHAuthorizationStatus) -> Void in
                ()
            })
        }
        
        if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized {
            self.createAlbum()
        } else {
            PHPhotoLibrary.requestAuthorization(requestAuthorizationHandler)
        }
    }
    
    func requestAuthorizationHandler(status: PHAuthorizationStatus) {
        if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized {
            // ideally this ensures the creation of the photo album even if authorization wasn't prompted till after init was done
            print("trying again to create the album")
            self.createAlbum()
        } else {
            print("should really prompt the user to let them know it's failed")
        }
    }
    
    private func createAlbum() {
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: CustomPhotoAlbum.albumName)   // create an asset collection with the album name
        }) { success, error in
            if success {
                self.assetCollection = self.fetchAssetCollectionForAlbum()
            } else {
                print("error \(error.debugDescription)")
            }
        }
        
    }
    
//    func deleteAlbum() {
//        let fetchOptions = PHFetchOptions()
//        fetchOptions.predicate = NSPredicate(format: "title = %@", CustomPhotoAlbum.albumName)
//        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
//        
//        PHPhotoLibrary.shared().performChanges({
//            PHAssetCollectionChangeRequest.deleteAssetCollections(collection)
//            
//        }) { success, error in
//            if success {
//                print("Deleted all !")
//            } else {
//                print("error \(error.debugDescription)")
//            }
//        }
//        
//    }
    
    func fetchAssetCollectionForAlbum() -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", CustomPhotoAlbum.albumName)
        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        
        if let _: AnyObject = collection.firstObject {
            return collection.firstObject
        }
        return nil
    }
    
    func save(image: UIImage, isRemote: Bool) -> String? {
        if assetCollection == nil {
            return nil                          // if there was an error upstream, skip the save
        }
        
        let imageData = UIImageJPEGRepresentation(image, 0.8)!
        let docDir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var name = NSDate().timeIntervalSince1970.description
        
        name = isRemote ? "\(name)_remo.png" : "\(name)_came.JPG"
        
        let imageURL = docDir.appendingPathComponent(name)
        try! imageData.write(to: imageURL)
        do {
            try PHPhotoLibrary.shared().performChangesAndWait({
                let assetChangeRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                let assetPlaceHolder = assetChangeRequest.placeholderForCreatedAsset
                let albumChangeRequest = PHAssetCollectionChangeRequest(for: self.assetCollection)
                let enumeration: NSArray = [assetPlaceHolder!]
                albumChangeRequest!.addAssets(enumeration)
                
            })
        }
        catch {
            return nil
        }
        return imageURL.absoluteString
    }
}

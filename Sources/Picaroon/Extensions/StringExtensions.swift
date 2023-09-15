import Foundation
import Hitch

public extension String {
    func percentEncoded() -> String? {
        // urlQueryAllowed character set have many notable omissions, but most egregiously are
        // "/" and "+". But we don't want to just ignore urlQueryAllowed (in case others are
        // added in the future) so we escape using the one and then the other
        //let notAllowedCharacterSet = CharacterSet(charactersIn: "!*'();:@&=+$,/?#[] ").inverted
        
        let notAllowedCharacterSet = CharacterSet.urlQueryAllowed.subtracting(
            CharacterSet(charactersIn: "!*'();:@&=+$,/?#[] ")
        )
        
        return self.addingPercentEncoding(withAllowedCharacters: notAllowedCharacterSet)
    }
}

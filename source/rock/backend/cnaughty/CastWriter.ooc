import structs/[List, ArrayList, HashMap]
import ../../middle/[Cast, InterfaceDecl, TypeDecl]
import Skeleton

CastWriter: abstract class extends Skeleton {

    write: static func ~cast (this: This, cast: Cast) {
        
        if(cast inner getType() isGeneric() && cast inner getType() pointerLevel() == 0) {
            
            current app("(* ("). app(cast type). app("*)"). app(cast inner). app(')')
            
        } else if(cast getType() getRef() instanceOf(InterfaceDecl)) {
            
            iDecl := cast getType() getRef() as InterfaceDecl
            current app("(struct _"). app(iDecl getFatType() getInstanceType()). app(") {").
                app(".impl = "). app(cast inner getType() getRef() as TypeDecl underName()). app("__impl__"). app(iDecl getName()). app("_class(), .obj = (lang_types__Object*) ").
                app(cast inner). app('}')
                
        } else {
            
            current app("(("). app(cast type). app(") "). app(cast inner). app(')')
            
        }
        
    }
    
}


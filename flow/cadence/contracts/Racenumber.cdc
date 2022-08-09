import NonFungibleToken from "./NonFungibleToken.cdc"
import FlowToken from "./FlowToken.cdc"
import FungibleToken from "./FungibleToken.cdc"
pub contract Racenumber:NonFungibleToken {
    pub var totalSupply:UInt64

    pub let EventsStoragePath:StoragePath
    pub let EventsPublicPath:PublicPath
    pub let NumberNFTCollectionStoragePath: StoragePath
    pub let NumberNFTCollectionPublicPath:PublicPath
    pub let ThemeNFTCollectionStoragePath: StoragePath
    pub let ThemeNFTCollectionPublicPath:PublicPath

    //Event相关Metadata
    pub struct EventDetail{
        pub var hostAddr:Address
        pub var name:String
        pub var totalSupply:UInt64
        pub var startDate: UInt32
        pub var id:UInt64
        pub var price:UFix64
        pub(set) var imgUrl: String;
        pub(set) var types:[UInt8];

        init(hostAddr:Address,name:String, totalSupply:UInt64, startDate: UInt32, id:UInt64,price:UFix64) {
            self.hostAddr = hostAddr
            self.name = name
            self.totalSupply = totalSupply
            self.startDate = startDate
            self.id = id
            self.imgUrl = ""
            self.types = []
            self.price = price
        }
    }

    //Number NFT相关Metadata
    pub struct NumberNFTMeta{
        pub let id:UInt64
        pub let eventId:UInt64
        pub let name:String
        pub let host:Address

        init(id:UInt64,eventId:UInt64,name:String, host:Address){
            self.id = id
            self.eventId = eventId
            self.name = name
            self.host = host
        }
    }
    //theme相关metadata
    pub struct ThemeMeta{
        pub let id:UInt64
        pub let eventId:UInt64
        pub let name:String
        pub let host:Address
        pub let type:UInt8

        init(id:UInt64,eventId:UInt64,name:String,host:Address,type:UInt8){
            self.id = id
            self.eventId = eventId
            self.name = name
            self.host = host
            self.type = type
        }
    }

    access(contract) var allEvents:{UInt64:EventDetail}  //每个主办方办的所有比赛,通过Events的Capability找到每个event

    //不用触发事件，接口必须
    pub event ContractInitialized()
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)

//B端创建比赛的模板
    pub resource interface  EventsPublic {
        pub var totalEvents:UInt64
        pub fun getAllEvents():{UInt64:String}
        pub fun borrowPublicEventRef(eventId: UInt64): &Event{EventPublic}
    }
    pub resource Events:EventsPublic {
        pub var totalEvents:UInt64
        access(contract) var events: @{UInt64:Event}
        pub fun createEvent(name:String, totalSupply:UInt64, startDate: UInt32, hostAddr: Address): UInt64 {
            let eventId = self.totalEvents;
            let price = 1.0
            let event <- create Event(name:name,totalSupply:totalSupply, startDate: startDate, hostAddr: hostAddr,eventId:eventId,price:price);
            self.events[eventId] <-! event
            let id = (&self.events[eventId] as &Event?)!.id
            assert(!Racenumber.allEvents.containsKey(id), message: "event id is not unique")
            let _eventDetail = EventDetail(hostAddr:hostAddr,name:name, totalSupply:totalSupply, startDate: startDate,id:id,price:price)
            Racenumber.allEvents.insert(key: id, _eventDetail)
            self.totalEvents = self.totalEvents + 1;
            return eventId;
        }
        
        //to do修改为正确的返回格式
        pub fun getAllEvents():{UInt64:String} {
            let res: {UInt64: String} = {}
            for id in self.events.keys {
                let ref = (&self.events[id] as &Event?)!
                res[id] = ref.name;
            }
            return res
        }
        
        pub fun borrowEventRef(eventId: UInt64): &Event{
          pre {
                self.events[eventId]!= nil:"Event not exist!"
            }
            return (&self.events[eventId] as &Event?)!
        }
        pub fun borrowPublicEventRef(eventId: UInt64): &Event{EventPublic} {
            pre {
                self.events[eventId]!= nil:"Event not exist!"
            }
            return (&self.events[eventId] as &Event{EventPublic}?)!
        }

        init() {
            self.totalEvents = 0
            self.events <- {}
        }

        destroy()  {
            destroy self.events
        }
    }
    pub resource interface EventPublic{
        pub fun mintNumber(num:UInt64, recipient: &Collection{NonFungibleToken.CollectionPublic},flowVault:@FlowToken.Vault)
        pub fun mintTheme(type:UInt8,recipient: &ThemeCollection{ThemeCollectionPublic})
        pub fun canMintTheme(addr:Address) :Bool
        pub var price:UFix64
    }
    pub resource Event:EventPublic {
        pub var id:UInt64;
        pub var totalSupply:UInt64;
        access(contract) var minted:{UInt64:Address};
        access(contract) var mintedAddrs:[Address];
        access(contract) var themeMintedAddrs:[Address];
        pub var name: String;
        pub var startDate: UInt32;
        pub let hostAddr: Address
        pub let eventId: UInt64;
        pub var imgUrl: String;
        pub var price: UFix64;
        access(contract) var types:[UInt8];
        
        //用户mint
        pub fun mintNumber(num:UInt64, recipient: &Collection{NonFungibleToken.CollectionPublic}, flowVault:@FlowToken.Vault) {
            pre {
                num < self.totalSupply: "This number exceed the totalSupply!"
                !self.minted.containsKey(num) : "This number has been minted!"
                
            }
            let addr:Address = recipient.owner!.address;
            assert(!self.mintedAddrs.contains(addr),message:"Your address has minted!")
            let token <- create NFT(
                host: self.hostAddr,
                eventId: self.eventId,
                name: self.name,
                num:num
                )
            let hostVault = getAccount(self.hostAddr).getCapability<&FlowToken.Vault{FungibleToken.Receiver}>(FlowToken.FlowTokenVaultPublic).borrow() ?? panic("Host addr Vault not found")
            hostVault.deposit(from: <-flowVault)
            self.minted.insert(key:num,addr);
            self.mintedAddrs.append(addr)
            recipient.deposit(token: <-token)
        }
        pub fun mintTheme(type:UInt8,recipient: &ThemeCollection{ThemeCollectionPublic}){
            pre{
                self.types.contains(type):"Theme Type doesn't exist!"
            }
            let addr = recipient.owner!.address;
            assert(!self.themeMintedAddrs.contains(addr),message:"Your address has minted theme NFT!")
            assert(self.mintedAddrs.contains(addr), message: "You donn't own Number NFT, has no permission to mint!")
            let nft <- create ThemeNFT(eventId: self.eventId, name: self.name, host: self.hostAddr, type: type, owner: addr)
            self.themeMintedAddrs.append(addr)
            recipient.deposit(token: <-nft)

        }

        pub fun canMintTheme(addr:Address) :Bool{
            return self.mintedAddrs.contains(addr)
        }

        init(name:String,totalSupply:UInt64, startDate: UInt32, hostAddr: Address, eventId:UInt64,price:UFix64) {
            self.name = name;
            self.totalSupply = totalSupply;
            self.startDate = startDate;
            self.hostAddr = hostAddr;
            self.eventId = eventId;
            self.minted = {};
            self.imgUrl = "";
            self.types = [];
            self.id = self.uuid
            self.mintedAddrs = []
            self.themeMintedAddrs = []
            self.price = price
        }
        
        pub fun setImgAndTypes(imgUrl:String, types: [UInt8]) {
            let id = self.uuid
            let ref = &Racenumber.allEvents[id]! as &EventDetail
            ref.imgUrl = imgUrl
            ref.types = types
            self.imgUrl = imgUrl;
            self.types = types;
        }
        
        destroy (){

        }

    }

//////////用户存储部分//////////////////
    pub resource interface CollectionPublic{
        pub fun deposit(token:@NonFungibleToken.NFT)
        pub fun getIDs():[UInt64]
        pub fun borrowNFT(id:UInt64): &NonFungibleToken.NFT
        pub fun borrowNumberNFT(id:UInt64):&NFT
    }
    pub resource NFT:NonFungibleToken.INFT {
        pub let id:UInt64
        pub let eventId:UInt64
        pub let name:String
        pub let host:Address
        pub let eventsCap: Capability<&Events>
        init(host:Address, eventId:UInt64, name:String,num:UInt64){
            //校验
            self.id = num
            self.eventId = eventId
            self.name = name
            self.host = host
            self.eventsCap = getAccount(host).getCapability<&Events>(Racenumber.EventsPublicPath)
        }     

        destroy (){
        }

    }

    pub resource ThemeNFT:NonFungibleToken.INFT {
        pub let id:UInt64
        pub let eventId:UInt64
        pub let name:String
        pub let host:Address
        pub let numberNFTCap: Capability<&NFT>
        pub let type:UInt8
        init(eventId:UInt64,name:String,host:Address, type:UInt8,owner:Address) {
            self.id = self.uuid
            self.eventId = eventId
            self.name = name
            self.host = host
            self.type = type
            self.numberNFTCap = getAccount(host).getCapability<&NFT>(Racenumber.NumberNFTCollectionPublicPath)  //并不能完全绑定上这个NFT
        }
    }

    pub resource Collection: NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, CollectionPublic {
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        pub fun withdraw(withdrawID:UInt64):@NonFungibleToken.NFT {
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("You donnot own this NFT")
            let nft <- token as! @NFT
            return <- nft
        }

        pub fun deposit(token:@NonFungibleToken.NFT) {
            let nft <- token as! @NFT;
            let id = nft.id;
            self.ownedNFTs[id]<-! nft;
        }

        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys;
        }

        pub fun borrowNFT(id:UInt64): &NonFungibleToken.NFT {
            return (&self.ownedNFTs[id] as &NonFungibleToken.NFT?)!
        }

        pub fun borrowNumberNFT(id:UInt64): &NFT{
            pre{
                self.ownedNFTs[id]!=nil: "Number NFT doesn't exist!"
            }
            let ref = (&self.ownedNFTs[id] as auth&NonFungibleToken.NFT?)!
            return ref as! &NFT
        }

        init(){
            self.ownedNFTs <- {}
        }
        destroy (){
            destroy self.ownedNFTs
        }
    }

    pub resource interface ThemeCollectionPublic {
        pub fun deposit(token:@ThemeNFT)
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id:UInt64): &ThemeNFT
    }

    pub resource ThemeCollection:ThemeCollectionPublic {
        pub var ownedNFTs: @{UInt64: ThemeNFT}

        pub fun withdraw(withdrawID:UInt64):@ThemeNFT {
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("You donnot own this NFT")
            return <- token
        }

        pub fun deposit(token:@ThemeNFT) {
            let nft <- token as! @ThemeNFT;
            let id = nft.id;
            self.ownedNFTs[id]<-! nft;
        }

        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys;
        }

        pub fun borrowNFT(id:UInt64): &ThemeNFT {
            pre {
                self.ownedNFTs[id]!=nil: "Theme NFT doesn't exist!"
            }
            return (&self.ownedNFTs[id] as &ThemeNFT?)!
        }

        init(){
            self.ownedNFTs <- {}
        }
        destroy (){
            destroy self.ownedNFTs
        }
    }

    pub fun createEmptyCollection(): @Collection {
        return <- create Collection()
    }

    pub fun createEmptyThemeCollection(): @ThemeCollection {
        return <- create ThemeCollection()
    }

    pub fun createEmptyEvents():@Events{
        return <- create Events();
    }

    //一些查询功能
    pub fun getAllEvents():{UInt64:EventDetail}{
        return self.allEvents
    }

    pub fun getEventById(id:UInt64):EventDetail{
        pre {
            self.allEvents[id] != nil:"event not exist!"
        }
        return self.allEvents[id]!
    }

    init() {
        self.EventsStoragePath = /storage/EventsStoragePath
        self.EventsPublicPath = /public/EventsStoragePath
        self.NumberNFTCollectionStoragePath = /storage/NumberNFTCollectionStoragePath
        self.NumberNFTCollectionPublicPath = /public/NumberNFTCollectionPublicPath
        self.ThemeNFTCollectionStoragePath = /storage/ThemeNFTCollectionStoragePath
        self.ThemeNFTCollectionPublicPath = /public/ThemeNFTCollectionPublicPath
        self.totalSupply = 0
        self.allEvents = {}
    }

}


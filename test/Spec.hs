{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

import           Control.Applicative             (liftA2)
import           Control.Monad                   (mapM_)
import qualified Data.Attoparsec.ByteString.Lazy as A
import qualified Data.ByteString                 as B
import qualified Data.ByteString.Char8           as BC
import qualified Data.ByteString.Lazy            as L
import           Data.Word                       (Word8)
import           Numeric                         (showHex)
import           Test.QuickCheck                 as QC
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck           as QC

import           Network.MQTT.Topic
import           Network.MQTT.Types              as MT

newtype SizeT = SizeT Int deriving(Eq, Show)

instance Arbitrary SizeT where
  arbitrary = SizeT <$> oneof [ choose (0, 127),
                                choose (128, 16383),
                                choose (16384, 2097151),
                                choose (2097152, 268435455)]

prop_rtLengthParser :: SizeT -> QC.Property
prop_rtLengthParser (SizeT x) =
  label (show (length e) <> "B") $
  d e == x

  where e = encodeLength x
        d :: [Word8] -> Int
        d l = case A.parse parseHdrLen (L.pack l) of
                A.Fail{}     -> undefined
                (A.Done _ v) -> v

testPacketRT :: Assertion
testPacketRT = mapM_ tryParse [
  "\DLE0\NUL\EOTMQTT\EOT\198\SOH,\NUL\ACKsomeid\NUL\btmp/test\NUL\STXhi\NUL\ACKdustin\NUL\ACKpasswd",
  " \STX\SOH\NUL"
  ]

  where
    tryParse s = do
      let (A.Done _ x) = A.parse (parsePacket Protocol311) s
      case A.parse (parsePacket Protocol311) (toByteString Protocol311 x) of
        f@A.Fail{}    -> assertFailure (show f)
        (A.Done _ x') -> assertEqual (show s) x x'

instance Arbitrary LastWill where
  arbitrary = LastWill <$> arbitrary <*> arbitrary <*> astr <*> astr <*> arbitrary

instance Arbitrary ProtocolLevel where arbitrary = arbitraryBoundedEnum

instance Arbitrary ConnectRequest where
  arbitrary = do
    _username <- mastr
    _password <- mastr
    _connID <- astr
    _cleanSession <- arbitrary
    _keepAlive <- arbitrary
    _lastWill <- arbitrary
    _properties <- arbitrary

    pure ConnectRequest{..}

mastr :: Gen (Maybe L.ByteString)
mastr = fmap (L.fromStrict . BC.pack . getUnicodeString) <$> arbitrary

astr :: Gen L.ByteString
astr = L.fromStrict . BC.pack . getUnicodeString <$> arbitrary

instance Arbitrary QoS where
  arbitrary = arbitraryBoundedEnum

instance Arbitrary ConnACKFlags where
  arbitrary = ConnACKFlags <$> arbitrary <*> arbitrary <*> arbitrary
  shrink (ConnACKFlags b c pl)
    | null pl = []
    | otherwise = ConnACKFlags b c <$> shrink pl

instance Arbitrary PublishRequest where
  arbitrary = do
    _pubDup <- arbitrary
    _pubQoS <- arbitrary
    _pubRetain <- arbitrary
    _pubTopic <- astr
    _pubPktID <- if _pubQoS == QoS0 then pure 0 else arbitrary
    _pubBody <- astr
    _pubProps <- arbitrary
    pure PublishRequest{..}

instance Arbitrary PubACK where
  arbitrary = PubACK <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary PubREL where
  arbitrary = PubREL <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary PubREC where
  arbitrary = PubREC <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary PubCOMP where
  arbitrary = PubCOMP <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary SubscribeRequest where
  arbitrary = arbitrary >>= \pid -> choose (1,11) >>= \n -> SubscribeRequest pid <$> vectorOf n sub <*> arbitrary
    where sub = liftA2 (,) astr arbitrary

  shrink (SubscribeRequest w s p) =
    if length s < 2 then []
    else [SubscribeRequest w (take 1 s) p' | p' <- shrinkList (:[]) p, length p > 1]

instance Arbitrary SubOptions where
  arbitrary = SubOptions <$> arbitraryBoundedEnum <*> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary SubErr where arbitrary = arbitraryBoundedEnum

instance Arbitrary SubscribeResponse where
  arbitrary = arbitrary >>= \pid -> choose (1,11) >>= \n -> SubscribeResponse pid <$> vectorOf n arbitrary <*> arbitrary

  shrink (SubscribeResponse pid l props)
    | length l == 1 = []
    | otherwise = [SubscribeResponse pid sl props | sl <- shrinkList (:[]) l, not (null sl)]

instance Arbitrary UnsubscribeRequest where
  arbitrary = arbitrary >>= \pid -> choose (1,11) >>= \n -> UnsubscribeRequest pid <$> vectorOf n astr <*> arbitrary
  shrink (UnsubscribeRequest p l props)
    | length l == 1 = []
    | otherwise = [UnsubscribeRequest p sl props | sl <- shrinkList (:[]) l, not (null sl)]

instance Arbitrary UnsubscribeResponse where
  arbitrary = UnsubscribeResponse <$> arbitrary <*> arbitrary

instance Arbitrary MT.Property where
  arbitrary = oneof [
    PropPayloadFormatIndicator <$> arbitrary,
    PropMessageExpiryInterval <$> arbitrary,
    PropMessageExpiryInterval <$> arbitrary,
    PropContentType <$> astr,
    PropResponseTopic <$> astr,
    PropCorrelationData <$> astr,
    PropSubscriptionIdentifier <$> arbitrary `suchThat` (>= 0),
    PropSessionExpiryInterval <$> arbitrary,
    PropAssignedClientIdentifier <$> astr,
    PropServerKeepAlive <$> arbitrary,
    PropAuthenticationMethod <$> astr,
    PropAuthenticationData <$> astr,
    PropRequestProblemInformation <$> arbitrary,
    PropWillDelayInterval <$> arbitrary,
    PropRequestResponseInformation <$> arbitrary,
    PropResponseInformation <$> astr,
    PropServerReference <$> astr,
    PropReasonString <$> astr,
    PropReceiveMaximum <$> arbitrary,
    PropTopicAliasMaximum <$> arbitrary,
    PropTopicAlias <$> arbitrary,
    PropMaximumQoS <$> arbitrary,
    PropRetainAvailable <$> arbitrary,
    PropUserProperty <$> astr <*> astr,
    PropMaximumPacketSize <$> arbitrary,
    PropWildcardSubscriptionAvailable <$> arbitrary,
    PropSubscriptionIdentifierAvailable <$> arbitrary,
    PropSharedSubscriptionAvailable <$> arbitrary
    ]

instance Arbitrary AuthRequest where
  arbitrary = AuthRequest <$> arbitrary <*> arbitrary

instance Arbitrary ConnACKRC where arbitrary = arbitraryBoundedEnum

instance Arbitrary DiscoReason where arbitrary = arbitraryBoundedEnum

instance Arbitrary DisconnectRequest where
  arbitrary = DisconnectRequest <$> arbitrary <*> arbitrary

instance Arbitrary MQTTPkt where
  arbitrary = oneof [
    ConnPkt <$> arbitrary,
    ConnACKPkt <$> arbitrary,
    PublishPkt <$> arbitrary,
    PubACKPkt <$> arbitrary,
    PubRELPkt <$> arbitrary,
    PubRECPkt <$> arbitrary,
    PubCOMPPkt <$> arbitrary,
    SubscribePkt <$> arbitrary,
    SubACKPkt <$> arbitrary,
    UnsubscribePkt <$> arbitrary,
    UnsubACKPkt <$> arbitrary,
    pure PingPkt, pure PongPkt,
    DisconnectPkt <$> arbitrary,
    AuthPkt <$> arbitrary
    ]
  shrink (SubACKPkt x)      = SubACKPkt <$> shrink x
  shrink (ConnACKPkt x)     = ConnACKPkt <$> shrink x
  shrink (UnsubscribePkt x) = UnsubscribePkt <$> shrink x
  shrink (SubscribePkt x)   = SubscribePkt <$> shrink x
  shrink _                  = []

prop_PacketRT50 :: MQTTPkt -> QC.Property
prop_PacketRT50 p = label (lab p) $ case A.parse (parsePacket Protocol50) (toByteString Protocol50 p) of
                                         A.Fail{}     -> False
                                         (A.Done _ r) -> r == p

  where lab x = let (s,_) = break (== ' ') . show $ x in s

prop_PacketRT311 :: MQTTPkt -> QC.Property
prop_PacketRT311 p = available p ==>
  let p' = v311mask p in
    label (lab p') $ case A.parse (parsePacket Protocol311) (toByteString Protocol311 p') of
                      A.Fail{}     -> False
                      (A.Done _ r) -> r == p'

  where
    lab x = let (s,_) = break (== ' ') . show $ x in s
    v311mask :: MQTTPkt -> MQTTPkt
    v311mask (ConnPkt c) = ConnPkt (c{_properties=mempty, _lastWill=cl <$> _lastWill c})
      where cl lw = lw{_willProps=mempty}
    v311mask (ConnACKPkt (ConnACKFlags a b _)) = ConnACKPkt (ConnACKFlags a b mempty)
    v311mask (SubscribePkt (SubscribeRequest p s _)) = SubscribePkt (SubscribeRequest p c mempty)
      where c = map (\(k,SubOptions{..}) -> (k,subOptions{_subQoS=_subQoS})) s
    v311mask (SubACKPkt (SubscribeResponse p s _)) = SubACKPkt (SubscribeResponse p s mempty)
    v311mask (UnsubscribePkt (UnsubscribeRequest p l _)) = UnsubscribePkt (UnsubscribeRequest p l mempty)
    v311mask (UnsubACKPkt (UnsubscribeResponse p _)) = UnsubACKPkt (UnsubscribeResponse p mempty)
    v311mask (PublishPkt req) = PublishPkt req{_pubProps=mempty}
    v311mask (DisconnectPkt _) = DisconnectPkt (DisconnectRequest DiscoNormalDisconnection mempty)
    v311mask (PubACKPkt (PubACK x _ _)) = PubACKPkt (PubACK x 0 mempty)
    v311mask (PubRECPkt (PubREC x _ _)) = PubRECPkt (PubREC x 0 mempty)
    v311mask (PubRELPkt (PubREL x _ _)) = PubRELPkt (PubREL x 0 mempty)
    v311mask (PubCOMPPkt (PubCOMP x _ _)) = PubCOMPPkt (PubCOMP x 0 mempty)
    v311mask x = x

    available (AuthPkt _) = False
    available _           = True

prop_PropertyRT :: MT.Property -> QC.Property
prop_PropertyRT p = label (lab p) $ case A.parse parseProperty (toByteString Protocol50 p) of
                                    A.Fail{}     -> False
                                    (A.Done _ r) -> r == p

  where lab x = let (s,_) = break (== ' ') . show $ x in s

prop_SubOptionsRT :: SubOptions -> Bool
prop_SubOptionsRT o = case A.parse parseSubOptions (toByteString Protocol50 o) of
                      A.Fail{}     -> False
                      (A.Done _ r) -> r == o

prop_PropertiesRT :: [MT.Property] -> Bool
prop_PropertiesRT p = case A.parse (parseProperties Protocol50) (bsProps Protocol50 p) of
                        A.Fail{}     -> False
                        (A.Done _ r) -> r == p

testTopicMatching :: [TestTree]
testTopicMatching = let allTopics = ["a", "a/b", "a/b/c/d", "b/a/c/d",
                                     "$SYS/a/b", "a/$SYS/b"]
                        tsts = [("a", ["a"]), ("a/#", ["a/b", "a/b/c/d"]),
                                ("+/b", ["a/b"]),
                                ("+/+/c/+", ["a/b/c/d", "b/a/c/d"]),
                                ("+/+/b", []),
                                ("+/$SYS/b", ["a/$SYS/b"]),
                                ("$SYS/#", ["$SYS/a/b"]),
                                ("+/$SYS/+", ["a/$SYS/b"]),
                                ("#/b", [])] in
    map (\(p,want) -> testCase (show p) $ assertEqual "" want (filter (match p) allTopics)) tsts

byteRT :: (ByteSize a, Show a, Eq a) => a -> Bool
byteRT x = x == (fromByte . toByte) x

tests :: [TestTree]
tests = [
  localOption (QC.QuickCheckTests 10000) $ testProperty "header length rt (parser)" prop_rtLengthParser,

  testCase "rt some packets" testPacketRT,
  localOption (QC.QuickCheckTests 1000) $ testProperty "rt packets 3.11" prop_PacketRT311,
  localOption (QC.QuickCheckTests 1000) $ testProperty "rt packets 5.0" prop_PacketRT50,
  localOption (QC.QuickCheckTests 1000) $ testProperty "rt property" prop_PropertyRT,
  testProperty "rt properties" prop_PropertiesRT,
  testProperty "sub options" prop_SubOptionsRT,

  testProperty "conn reasons" (byteRT :: ConnACKRC -> Bool),
  testProperty "disco reasons" (byteRT :: DiscoReason -> Bool),

  testGroup "topic matching" testTopicMatching
  ]

main :: IO ()
main = defaultMain $ testGroup "All Tests" tests

-- |
-- Module      : Web.FBMessenger.API.Bot.Requests 
-- License     : BSD3
-- Maintainer  : Marcello Seri <marcello.seri@gmail.com>
-- Stability   : experimental
-- Portability : unknown
--
-- This module contains types and helpers to parse the webhook requests coming
-- from the <https://developers.facebook.com/docs/messenger-platform/ Messenger Platform API>. 
-- You can find a complete example with the source code of this library on
-- <https://github.com/mseri/fbmessenger-api-hs/blob/master/example-app/example.hs github>.
-- 
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE TypeOperators              #-}

module Web.FBMessenger.API.Bot.WebhookAPI (
    -- * Types
      RemoteEvent                      (..)
    , RemoteEventList                  (..)
    , EventMessage                     (..)
    , EventMessageContent              (..) 
    , EventMessageAttachment           (..)
    , EventMessageAttachmentType       (..)
    -- * Functions
    , extractMessagingEvents
) where
    
import           Control.Monad (when)
import           Data.Aeson
import           Data.HashMap.Lazy (member)
import           Data.Text (Text)
import           GHC.Generics
import           Web.FBMessenger.API.Bot.JsonExt

-- TODOS: * add docstrings
--        * try to cleanup and simplify the API and the data representation 
--        * consider adding useful getters and a mapper from [RemoteEvents] -> [EventMessage]

-- | This type wraps the content of a webhook request
data RemoteEventList = RemoteEventList [RemoteEvent] deriving (Eq, Show)
instance ToJSON RemoteEventList where
    toJSON (RemoteEventList evts) = object [ "object" .= ("page"::String), "entry" .= evts ]
instance FromJSON RemoteEventList where
    parseJSON = withObject "webhook request" $ \o -> do
                  obj <- o .: "object"
                  when (obj /= ("page"::String)) $ 
                    fail "invalid messaging event request"
                  evts <- o .: "entry"
                  return (RemoteEventList evts)

-- | A webhook request contains a list of 'RemoteEvents', objects containing 
--   an id, a time and a list of messaging events.
data RemoteEvent = RemoteEvent
    { evt_id        :: Text             -- ^ Page ID of page 
    , evt_time      :: Int              -- ^ Time of update
    , evt_messaging :: [EventMessage]   -- ^ Array containing objects related to messaging
    } deriving (Show, Eq, Generic)

instance ToJSON RemoteEvent where
    toJSON = toJsonDrop 4
instance FromJSON RemoteEvent where
    parseJSON = parseJsonDrop 4

-- | This is an event message, for additional information refer to the official
--   Messenger Platform API.
data EventMessage = EventMessage 
    { evtSenderId    :: Text            -- ^ Sender user ID
    , evtRecipientId :: Text            -- ^ Recipient user ID
    , evtTimestamp   :: Maybe Int
    , evtContent     :: EventMessageContent
    } deriving (Show, Eq)

instance ToJSON EventMessage where 
    toJSON EventMessage{..} = 
        let content = case evtContent of 
                        EmTextMessage{}       -> "message"
                        EmStructuredMessage{} -> "message"
                        EmAuth{}              -> "optin"
                        EmDelivery{}          -> "delivery"
                        EmPostback{}          -> "postback"
        in omitNulls [ "sender"    .= object [ "id" .= evtSenderId ]
                     , "recipient" .= object [ "id" .= evtRecipientId ] 
                     , "timestamp" .= evtTimestamp
                     , content     .= evtContent ]
                            
instance FromJSON EventMessage where
    parseJSON = withObject "WebSocket message content" $ \o -> do
                  evtSenderId    <- o .: "sender" >>= (.: "id")
                  evtRecipientId <- o .: "recipient" >>= (.: "id")
                  evtTimestamp   <- o .:? "timestamp"
                  -- not too clean but does the job
                  -- if we refactor, it's maybe faster if we get the first true only
                  let evtChoices = filter (`member` o) (["message", "optin", "delivery", "postback"]::[Text])
                  when (null evtChoices) $ 
                    fail "unknown message content"
                  -- WARN: here I am assuming only one kind of content per request
                  evtContent <- o .: head evtChoices 
                  return EventMessage{..}

-- | Helper to extract all messaging events from the 'RemoteEventList' in the 
--   webhook call body
extractMessagingEvents :: RemoteEventList -> [EventMessage]
extractMessagingEvents (RemoteEventList res) = concatMap evt_messaging res

data EventMessageContent = EmTextMessage Text Int Text       -- ^ Message ID; Message sequence number; Message text. 
                         | EmStructuredMessage Text Int [EventMessageAttachment] -- ^ Message ID; Message sequence number; Array containing attachment data (image, video, audio)
                         | EmAuth Text                       -- ^ data-ref parameter that was defined with the entry point
                         | EmDelivery Int Int (Maybe [Text]) -- ^ Sequence No.; Watermark: all messages that were sent before this timestamp were delivered; Array containing message IDs of messages that were delivered (optional) 
                         | EmPostback Text                   -- ^ Contains the postback payload that was defined with the button
                         deriving (Show, Eq)
instance ToJSON EventMessageContent where
    toJSON (EmTextMessage mid seq text) = object [ "mid" .= mid, "seq" .= seq, "text" .= text ] 
    toJSON (EmStructuredMessage mid seq attachments) = object [ "mid" .= mid, "seq" .= seq, "attachments" .= attachments ]
    toJSON (EmAuth ref) = object [ "ref" .= ref ]
    toJSON (EmDelivery seq watermark mids) = omitNulls [ "seq" .= seq, "watermark" .= watermark, "mids" .= mids ]
    toJSON (EmPostback payload) = object [ "payload" .= payload ]
    
instance FromJSON EventMessageContent where
    parseJSON = withObject "message content" $ \o -> do
        let ctChoices = filter (`member` o) (["text", "attachments", "ref", "watermark", "payload"]::[Text])
        when (null ctChoices) $ 
            fail "unknown message content"
        case head ctChoices of
            "text"        -> EmTextMessage <$> o .: "mid" <*> o .: "seq" <*> o .: "text"
            "attachments" -> EmStructuredMessage <$> o .: "mid"  <*> o .: "seq" <*> o .: "attachments"
            "ref"         -> EmAuth <$> o .: "ref"
            "watermark"   -> EmDelivery <$> o .: "seq" <*> o .: "watermark" <*> o .:? "mids"
            "payload"     -> EmPostback <$> o .: "payload"
            _             -> error "this cannot happen by construction, but I want to make the compiler happy"


data EventMessageAttachment = EmAttachment { emType :: EventMessageAttachmentType, emUrl :: Text } deriving (Show, Eq)
instance ToJSON EventMessageAttachment where
    toJSON EmAttachment{..} = object [ "type" .= emType, "payload" .= object [ "url" .= emUrl ] ]
instance FromJSON EventMessageAttachment where
    parseJSON = withObject "websocket call message attachment" $ \o -> do
        emType <- o .: "type"
        emUrl  <- o .: "payload" >>= (.: "url")
        return EmAttachment{..} 
    
data EventMessageAttachmentType = EmImage | EmVideo | EmAudio deriving (Show, Eq)
instance ToJSON EventMessageAttachmentType where
    toJSON EmImage = "image"
    toJSON EmVideo = "video"
    toJSON EmAudio = "audio" 
instance FromJSON EventMessageAttachmentType where
    parseJSON "image" = pure EmImage
    parseJSON "video" = pure EmVideo
    parseJSON "audio" = pure EmAudio
    parseJSON _       = fail "impossible to parse AttachmentType"
    


-- Helpers

-- from http://bitemyapp.com/posts/2014-07-31-aeson-with-uncertainty-revised.html
omitNulls :: [(Text, Value)] -> Value
omitNulls = object . filter notNull where
  notNull (_, Null) = False
  notNull _         = True

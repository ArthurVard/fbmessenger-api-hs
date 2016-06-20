-- |
-- Module      : Web.FBMessenger.API.Bot.Requests 
-- License     : BSD3
-- Maintainer  : Marcello Seri <marcello.seri@gmail.com>
-- Stability   : experimental
-- Portability : unknown
--
-- This module contains a 'servant' client for the 
-- <https://developers.facebook.com/docs/messenger-platform/ Messenger Platform API>
-- and helpers useful to construct the appropriate requests and parse the responses.
--
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TypeOperators              #-}

module Web.FBMessenger.API.Bot.SendAPI 
  ( -- * Functions
    getUserProfileInfo
  , removeWelcomeMessage
  , sendTextMessage
  , sendStructuredMessage
  , setWelcomeMessage
  , subscribedApps
  , uploadImageMessage
    -- * API
  , api
  , FBMessengerSendAPI
    -- * Types
  , Token                  (..)
  ) where


import           Control.Monad.Trans.Except (runExceptT) -- ExceptT
import           Data.Proxy
import           Data.Text (Text)
import qualified Data.Text as T
import           Network.HTTP.Client (Manager)
import           Servant.API
import           Servant.Client
import           Servant.Client.MultipartFormData
import           Web.FBMessenger.API.Bot.Requests
import           Web.FBMessenger.API.Bot.Responses


-- | Messenger Platform PAGE_ACCESS_TOKEN
newtype Token = Token Text
   deriving (Show, Eq, Ord, ToHttpApiData, FromHttpApiData)

-- | Type for token
-- NOTE: 'QueryParam' here gives us a 'Maybe Token'
type GraphAPIAccessToken = QueryParam "access_token" Token


-- Servant.Client.BaseUrl
graphAPIBaseUrl :: BaseUrl
graphAPIBaseUrl = BaseUrl Https "graph.facebook.com" 443 "/v2.6"


-- | Messenger Platform Send API
type FBMessengerSendAPI = 
         GraphAPIAccessToken :> "me" :> "messages" 
         :> ReqBody '[JSON] SendTextMessageRequest
         :> Post '[JSON] MessageResponse
    :<|> GraphAPIAccessToken :> "me" :> "messages"
         :> MultipartFormDataReqBody (UploadImageMessageRequest FileUpload)
         :> Post '[JSON] MessageResponse
    :<|> GraphAPIAccessToken :> "me" :> "messages" 
         :> ReqBody '[JSON] SendStructuredMessageRequest
         :> Post '[JSON] MessageResponse
    :<|> GraphAPIAccessToken :> "me" :> "subscribed_apps"
         :> Post '[JSON] SubscriptionResponse
    :<|> GraphAPIAccessToken :> Capture "page_id" Text :> "thread_settings"
         :> ReqBody '[JSON] WelcomeMessageRequest
         :> Post '[JSON] WelcomeMessageResponse
    :<|> GraphAPIAccessToken :> Capture "page_id" Text :> "thread_settings"
         :> ReqBody '[JSON] WelcomeMessageRequest
         :> Delete '[JSON] WelcomeMessageResponse
    :<|> GraphAPIAccessToken :> QueryParam "fields" Text :> Capture "user_id" Text
         :> Get '[JSON] UserProfileResponse


-- | Proxy for Messenger Platform Bot Send
api :: Proxy FBMessengerSendAPI
api = Proxy

-- type ClientM = ExceptT ServantError IO
sendTextMessage_       ::               Maybe Token -> SendTextMessageRequest -> Manager -> BaseUrl -> ClientM MessageResponse
uploadImageMessage_    :: Maybe Token -> UploadImageMessageRequest FileUpload -> Manager -> BaseUrl -> ClientM MessageResponse
sendStructuredMessage_ ::         Maybe Token -> SendStructuredMessageRequest -> Manager -> BaseUrl -> ClientM MessageResponse
subscribedApps_        ::                                         Maybe Token -> Manager -> BaseUrl -> ClientM SubscriptionResponse
welcomeMessage_        ::        Maybe Token -> Text -> WelcomeMessageRequest -> Manager -> BaseUrl -> ClientM WelcomeMessageResponse
deleteWMessage_        ::        Maybe Token -> Text -> WelcomeMessageRequest -> Manager -> BaseUrl -> ClientM WelcomeMessageResponse
userProfile_           ::                   Maybe Token -> Maybe Text -> Text -> Manager -> BaseUrl -> ClientM UserProfileResponse

sendTextMessage_
  :<|> uploadImageMessage_
  :<|> sendStructuredMessage_
  :<|> subscribedApps_ 
  :<|> welcomeMessage_
  :<|> deleteWMessage_
  :<|> userProfile_ = client api


-- | Send text messages. On success, minor informations on the sent message are returned.
sendTextMessage :: Maybe Token -> SendTextMessageRequest -> Manager -> IO (Either ServantError MessageResponse)
sendTextMessage = run graphAPIBaseUrl sendTextMessage_

-- | Upload an image and send a structured messages containing it. 
--   On success, minor informations on the sent message are returned.
uploadImageMessage :: Maybe Token -> UploadImageMessageRequest FileUpload -> Manager -> IO (Either ServantError MessageResponse)
uploadImageMessage = run graphAPIBaseUrl uploadImageMessage_

-- | Send a structured messages. This can be an image message (containing an image url) 
--   or any template message (generic, button, receipt).  
--   On success, minor informations on the sent message are returned.
sendStructuredMessage :: Maybe Token -> SendStructuredMessageRequest -> Manager -> IO (Either ServantError MessageResponse)
sendStructuredMessage = run graphAPIBaseUrl sendStructuredMessage_

-- | Test if your bot's auth token is enabled. Requires no parameters.
--   Return a simple object containing a boolean value indicating if the 
--   token is correctly registered.
subscribedApps :: Maybe Token -> Manager -> IO (Either ServantError SubscriptionResponse)
subscribedApps token manager = runExceptT $ subscribedApps_ token manager graphAPIBaseUrl

-- | Set a welcome message, this can be an image message (containing an image url) 
--   or any template message (generic, button, receipt).
--   In addition to the token and the message request, you need to provide the 
--   facebook page_id.
--   Return a simple object containing a string indicating if the welcome message 
--   is correctly registered.
setWelcomeMessage :: Maybe Token -> Text -> WelcomeMessageRequest -> Manager -> IO (Either ServantError WelcomeMessageResponse)
setWelcomeMessage token pageId message manager = runExceptT $ welcomeMessage_ token pageId message manager graphAPIBaseUrl

-- | Remove the welcome message. In addition to the token, you need to provide 
--   the facebook page_id.
--   Return a simple object containing a string indicating if the welcome 
--   message is correctly removed.
removeWelcomeMessage :: Maybe Token -> Text -> Manager -> IO (Either ServantError WelcomeMessageResponse)
removeWelcomeMessage token pageId manager = runExceptT $ deleteWMessage_ token pageId welcomeDeleteMessage manager graphAPIBaseUrl

-- | Get the profile informations of a user. In addition to the token, you need
--   to provide the user_id.
--   Return a record containing the profile informations.
getUserProfileInfo :: Maybe Token -> Text -> Manager -> IO (Either ServantError UserProfileResponse)
getUserProfileInfo token userId manager = runExceptT $ userProfile_ token userProfileFields userId manager graphAPIBaseUrl


-- Helpers (not exported)

userProfileFields :: Maybe Text
userProfileFields = pure $ T.pack "first_name,last_name,profile_pic,locale,timezone,gender"

welcomeDeleteMessage :: WelcomeMessageRequest
welcomeDeleteMessage = WelcomeEmptyMessage

run :: BaseUrl -> (Maybe Token -> a -> Manager -> BaseUrl -> ClientM b) -> Maybe Token -> a -> Manager -> IO (Either ServantError b)
run b e t r m = runExceptT $ e t r m b

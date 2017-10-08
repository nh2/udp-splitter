#!/usr/bin/env stack
-- stack --resolver lts-9.6 --install-ghc runghc --package network

module Main where

import           Control.Monad (forever, forM)
import           Data.Foldable (for_)
import           Data.List (intersperse, break)
import qualified Network.Socket as N
import           Network.Socket.ByteString (recvFrom, sendAllTo)
import           System.Environment (getProgName, getArgs)
import           System.Exit (die)
import           Text.Read (readMaybe)


getHostPort :: String -> IO (String, String)
getHostPort hostPort = case break (== ':') (reverse hostPort) of
  (rPort, ':':rHost) -> pure (reverse rHost, reverse rPort)
  _ -> die $ "Could not parse host:port from '" ++ hostPort ++ "'"


ipFamily :: N.SockAddr -> N.Family
ipFamily a = case a of
  N.SockAddrInet{} -> N.AF_INET
  N.SockAddrInet6{} -> N.AF_INET6
  _ -> error $ "ipFamily called on a non-IP socket address: " ++ show a


main :: IO ()
main = do
  progName <- getProgName
  let usageStr = "Usage: " ++ progName ++ " bindAddress:port (targetHost:port)..."
  args <- getArgs
  case args of
    [] -> die usageStr
    xs | "-h" `elem` xs || "--help" `elem` xs -> putStrLn usageStr
    bindHostPort:targetHostsPorts -> do

      let udpHints = N.defaultHints{ N.addrSocketType = N.Datagram, N.addrProtocol = 17 }

      (bindAddr, bindPort) <- do
        (host, port) <- getHostPort bindHostPort
        addrInfos <- N.getAddrInfo (Just udpHints) (Just host) (Just port)
        case addrInfos of
          [] -> die $ "Could not get local address info for " ++ bindHostPort
          a:_ -> pure (N.addrAddress a :: N.SockAddr, port)

      putStrLn $ "Listening on " ++ show bindAddr

      putStrLn "Resolving hosts..."

      hostAddrs <- forM targetHostsPorts $ \hostPort -> do
        (host, port) <- getHostPort hostPort
        -- Address resolution
        addrInfos <- N.getAddrInfo (Just udpHints) (Just host) (Just port)
        case addrInfos of
          [] -> die $ "Could not resolve host " ++ host
          a:_ -> pure (N.addrAddress a :: N.SockAddr)

      putStrLn $ "Forwarding to " ++ show (length hostAddrs) ++ " hosts:"
        ++ concatMap (\a -> "\n  - " ++ show a) hostAddrs

      -- Check for IPv6; if it's not used, we don't create a socket for it
      let usesIpv4 = any ((== N.AF_INET) . ipFamily) hostAddrs
      let usesIpv6 = any ((== N.AF_INET6) . ipFamily) hostAddrs

      -- Socket bind and packet loop
      N.withSocketsDo $ do
        inSock <- N.socket (ipFamily bindAddr) N.Datagram 0
        N.bind inSock bindAddr

        outSockIpv4 <- if usesIpv4 then N.socket N.AF_INET N.Datagram 0
                                   else pure (error "v4 socket should not be asked for")
        outSockIpv6 <- if usesIpv6 then N.socket N.AF_INET6 N.Datagram 0
                                   else pure (error "v6 socket should not be asked for")

        forever $ do
          (mesg, client) <- recvFrom inSock 65536
          for_ hostAddrs $ \addr -> case ipFamily addr of
            N.AF_INET -> sendAllTo outSockIpv4 mesg addr
            N.AF_INET6 -> sendAllTo outSockIpv6 mesg addr

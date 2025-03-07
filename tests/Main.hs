module Main where

import Test.Tasty (defaultMain)

import Clash.Tests.Laws.Finite

main :: IO ()
main = defaultMain tests

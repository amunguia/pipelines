{-|
Module      :  Control.Concurrent.Pipeline
Copyright   :  (c) Alejandro Munguia 2015
License     :  MIT (see the LICENSE file)
Maintainer  :  munguia.jandro@gmail.com
Stability   :  experimental
Portability :  portable

A Pipeline is a sequence of functions that successively transforms a 
stream of input data.  Each function runs asynchronously.  Additionally,
it is possible to execute a given  function accross any number of threads.

-}

module Control.Concurrent.Pipeline (
      begin
    , beginWithChan
    , end
    , endAndWait
    , input
    , output
    , waitOn
    , with
    , (&|)
    , (&|!)
    , (&/)
    , (&/!)
    , (>=>)
    , (>=<)
    ) where

import Control.Concurrent.Pipelines.Combinators
import Control.Concurrent.Pipelines.IO 
import Control.Concurrent.Pipelines.Lifecycle
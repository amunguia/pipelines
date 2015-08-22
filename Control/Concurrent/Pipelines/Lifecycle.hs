module Control.Concurrent.Pipelines.Lifecycle (
      begin 
    , beginWithChan
    , end 
    , endAndWait
    , waitOn
    ) where

import Control.Concurrent.Async (async, wait)
import Control.Concurrent.Chan
import Control.Concurrent.Pipelines.Internal

-- | Creates a new pipeline.
begin :: IO (Pipeline a a)
begin = newChan >>= beginWithChan

-- | Creates a new pipeline with a given input channel.
beginWithChan :: Chan a -> IO (Pipeline a a)
beginWithChan startChan = do
    chan <- newChan
    asyn <- async $ toJobResultChan startChan chan
    emp  <- async $ return ()
    return $ makePipeline chan chan asyn emp 

-- | Places an end signal, represented by JobEnd, into the input channel
end :: Pipeline a b -> IO (Pipeline a b)
end pipeline = writeChan (startChan pipeline) JobEnd >> (return pipeline)

-- | Places the end signal then blocks until the final thread returns
endAndWait :: Pipeline a b -> IO (Pipeline a b)
endAndWait pipeline = end pipeline >>= waitOn

-- | Blocks until the pipeline has completed execution
waitOn :: Pipeline a b -> IO (Pipeline a b)
waitOn pipeline = wait (endSync pipeline) >> (return pipeline) 
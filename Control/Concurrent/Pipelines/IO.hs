module Control.Concurrent.Pipelines.IO (
      input
    , output
    ) where

import Control.Concurrent.Chan
import Control.Concurrent.Pipelines.Internal

-- | Insert an item into the pipeline
input :: Pipeline a b -> a -> IO (Pipeline a b)
input pipeline a = writeChan (startChan pipeline) (JobResult a) >> (return pipeline)

-- | Retrieve an item from the end of the pipeline wrapped in a Maybe.
--   Returns Nothing if end signal found.
output :: Pipeline a b -> IO (Maybe b)
output pipeline = do
    b <- readChan $ endChan pipeline
    case b of
        JobResult b -> return $ Just b
        JobEnd      -> return Nothing
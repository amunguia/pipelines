module Control.Concurrent.Pipelines.Internal
 (
      Job (..)
    , JobResult (..)
    , Pipeline (..)
    , exec
    , toJobResultChan
    , makePipeline
    , multiSync
    , shovel
    , shovel2
    ) where

import Control.Concurrent.Chan 
import Control.Concurrent.Async (Async, link, wait)

-- | Wraps an input item. Uses JobEnd to determine if a pipeline is being closed.
data JobResult a  = JobResult a | JobEnd 

-- | A job in a pipeline is an input channel, an output channel, and a
--   function to transform data as it moves from the first to the second.
data Job  a b  = Job {
                 job        :: a -> IO b
               , inchan     :: Chan (JobResult a)
               , outchan    :: Chan (JobResult b) 
               } 

-- | A sequence of jobs to run asynchronously. The first job has type a, 
--   the final job has type b.
data Pipeline a b  = Pipeline {
                     startChan :: Chan (JobResult a) 
                   , endChan   :: Chan (JobResult b)
                   , startSync :: Async ()
                   , endSync   :: Async ()
                   }

-- | Runs the function specified by the job on one input. Returns if JobEnd is read 
--   from the input channel, otherwise repeats for next item.
exec :: Job a b -> IO ()
exec j = do
    a <- readChan $ inchan j
    case a of 
        JobResult a' -> do
            b <- (job j) a'
            writeChan (outchan j) (JobResult b)
            exec j 
        JobEnd -> do
            writeChan (inchan j) JobEnd  -- in case multiple readers
            writeChan (outchan j) JobEnd -- pass JobEnd signal
            return () 

-- | Move values from one channel to another, wrapping in JobResult in the process.
toJobResultChan :: Chan a -> Chan (JobResult a) -> IO ()
toJobResultChan chan jobResultChan = do
    a <- readChan chan
    writeChan jobResultChan $ JobResult a
    toJobResultChan chan jobResultChan

-- | Create a pipeline.
makePipeline :: Chan (JobResult a) -> Chan (JobResult b) -> Async () -> Async () -> Pipeline  a b
makePipeline ichan ochan a1 a2 = Pipeline {startChan=ichan, endChan=ochan, startSync=a1, endSync=a2}

-- | Links all the threads to the current thread and blocks until all return.
multiSync :: [Async ()] -> IO ()
multiSync syncs = do
    sequence_ $ fmap link syncs
    sequence_ $ fmap wait syncs
    return ()

-- | Moves values from chan to another. Terminating on JobEnd signal.
shovel :: Chan (JobResult a) -> Chan (JobResult a) -> Async () -> IO ()
shovel from to sync = do 
    link sync
    next <- readChan from
    case next of 
        JobResult a -> writeChan to (JobResult a) >> shovel from to sync
        JobEnd      -> writeChan to JobEnd >> return ()

shovel2 :: Chan (JobResult a) -> Chan (JobResult a) -> Chan (JobResult a) -> Async () -> IO ()
shovel2 from to1 to2 sync = do
    link sync
    next <- readChan from
    case next of 
        JobResult a -> writeChan to1 (JobResult a) >> 
                           writeChan to2 (JobResult a) >> 
                           shovel2 from to1 to2 sync
        JobEnd      -> writeChan to1 JobEnd >> 
                           writeChan to2 JobEnd >>  
                           return ()


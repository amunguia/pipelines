module Pipeline (
      begin
    , beginWithChan
    , end
    , endAndWait
    , input
    , output
    , waitOn
    , with
    , (&|)
    , (&/)
    ) where

import Control.Concurrent.Async (Async, async, link, link2, wait)
import Control.Concurrent.Chan

-- | Wraps an input item. Uses JobEnd to determine if job is complete.
data JobResult a  = JobResult a | JobEnd 


data Runner  a b  = Runner {
                    job        :: a -> IO b
                  , inchan     :: Chan (JobResult a)
                  , outchan    :: Chan (JobResult b) 
                  } 

-- | 
data Pipeline a b  = Pipeline {
                     startChan :: Chan (JobResult a) 
                   , endChan   :: Chan (JobResult b)
                   , startSync :: Async ()
                   , endSync   :: Async ()
                   }

-- | Runs the job specified by the runner. Returns if JobEnd is read from the 
--   input channel.
exec :: Runner a b -> IO ()
exec runner = do
    a <- readChan $ inchan runner
    case a of 
        JobResult a' -> do
            b <- (job runner) a'
            writeChan (outchan runner) (JobResult b)
            exec runner 
        JobEnd -> do
            writeChan (inchan runner) JobEnd  -- in case multiple readers
            writeChan (outchan runner) JobEnd -- pass JobEnd signal
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

-- | Appends a new job to a pipeline.
(&|) :: IO (Pipeline c a) -> (a -> IO b) -> IO (Pipeline c b)
(&|) pipeline func = do 
    p          <- pipeline
    outChan    <- newChan
    let runner = Runner {job=func, inchan=(endChan p), outchan=outChan}
    asyn       <- async $ exec runner
    link2 asyn (startSync p)
    return $ makePipeline (startChan p) outChan (startSync p) asyn

-- | Intended to be followed by a call to with. Appends a new function
--   to a pipeline. However, this does not start a job. Following with 
--   a call to with starts the job running in the specified number of
--   threads.
(&/) :: IO (Pipeline c a) -> (a -> b) -> (IO (Pipeline c a), a -> b)
(&/) pipeline func = (pipeline, func)

-- | Specifies how many threads to execute the last job in pipeline.
with :: (IO (Pipeline c a), a -> IO b) ->  Int -> IO (Pipeline c b)
with (pipeline, func) num = do
    p          <- pipeline
    outChan    <- newChan
    let runner = Runner {job=func, inchan=(endChan p), outchan=outChan}
    asyns      <- sequence $ fmap (async . exec) $ replicate num runner
    asyn       <- async $ multiSync asyns
    link2 asyn (startSync p)
    return $ makePipeline (startChan p) outChan (startSync p) asyn

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

-- | Blocks until the pipeline has completed execution
waitOn :: Pipeline a b -> IO (Pipeline a b)
waitOn pipeline = wait (endSync pipeline) >> (return pipeline) 


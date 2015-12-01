<?php
/*

example:

<?php

    $host['host'] = 'tcp://127.0.0.1:80';
    $host['uri'] = '/index.php';
    $host['hostname'] = '127.0.0.1';
    $host['content_type'] = 'application/json';
    $host['post_data'] = '{"a":1}';
    
    $hosts[] = $host;
    $hosts[] = $host;

    $ps = new C8HttpLib();

    $ps->http_post_multi($hosts);	//execute async requests
    $ps->run(); 			//start listening
    print_r($ps->getresponse());	//get response
?>

response:
     [type]
     [httpVersion]
     [responseCode]
     [responseStatus]
     [headers] => Array
                     (
                      ...
                     )
     [body]
     
*/

class C8HttpLib {

  private $streams = array();
  private $listeners = array();
  private $timeout = 1;	//init timeout
  private $response = array();
  private $microtime_init;
  private $conn_timeout_ms = 1000;
  
  //init constructor
  function __construct($arg = null)
  {
    //$this->microtime_init = microtime(true);
  }

  function add($arg1, $arg2 = null)
  {
    if (is_array($arg1))
    {
      foreach ($arg1 as $offset => $s)
      {
        //print_r($s);
      
        if (! is_array($s))
        {
          throw new C8HttpLibException("Illegal input at offset " . $offset . " (not an array)");
        } elseif (count($s = array_values($s)) < 2) {
          throw new C8HttpLibException("Illegal input at offset " . $offset . " (length is less then 2)");
        } elseif (! is_resource($s[0])) {
          throw new C8HttpLibException("Illegal input at offset " . $offset . " (not a stream resource)");
        } elseif (! is_callable($s[1])) {
          throw new C8HttpLibException("Illegal input at offset " . $offset . " (not a callable)");
        }

        $this->addOne($offset, $s[0], $s[1], $s[2]);
      }
    } elseif (is_resource($arg1)) {
      if (! is_callable($arg2))
      {
        throw new C8HttpLibException("Argument 2 is expected to be a callable, " . gettype($arg2) . " given");
      }
      $this->addOne($arg1, $arg2, $arg3);
    } else {
      throw new C8HttpLibException("Argument 1 is expected to be a resource or an array, " . gettype($arg1) . " given");
    }
  }
  
  /*
    listening to stream events
  */
  function run()
  {

    while (count($this->streams))
    {
	$events = $this->streams;
	//if timed out?
	if($this->conn_timeout_ms < (microtime(true)-$this->microtime_init))
	{
	    $this->processStreamEvents($events,array('response' => array('responseCode'=>'604','responseStatus'=>'Stream socket connection timeout')));
	}
	else
	{
	    //iteration ever 10 ms
    	    if (false === ($num_changed_streams = stream_select($events, $write, $except, 0, 10000)))
    	    {
    		return false; //init error, return false
    	    } elseif (count($events)) {
		$this->processStreamEvents($events, false); //process event -> read response in array
    	    } else {
		/* until next status check */
    	    }
    	}
    }
    return true;
  }

  /*
    init mult-connections
  */

  function http_post_multi($hosts)
  {
    //init time
    $this->microtime_init = microtime(true);
    //callback func
    $callback = function ($data, $id, $e = false) {
    
    if (!$e) 
    {
        $data['response'] = http_parse_message($data['response']);
        $this->response[$id] = $data;
    }
    elseif(@is_array($data))
    {
	$this->response[$id] = $data;
    }
    else
    {
	$this->response[$id] = null;
    }
     return ;
    };
    $streams = array();
    //init streams
    foreach ($hosts as $i=>$host) {
	if($host['uri'] &&
	    $host['host'] &&
	    $host['hostname'] &&
	    $host['content_type'] &&
	    $host['post_data'])
	{
	    $s = @stream_socket_client($host['host'], $errno, $errstr, $this->timeout);
	    if($s) {
		$http  = "POST " . $host['uri'] . " HTTP/1.0\r\n";
		$http .= "Host: " . $host['hostname'] . "\r\n";
		//$http .= "User-Agent: " . $_SERVER['HTTP_USER_AGENT'] . "\r\n";
		$http .= "Content-Type: " . $host['content_type'] . "\r\n";
		if($host['post_data']) $http .= "Content-length: " . (strlen($host['post_data'])+2) . "\r\n";
		$http .= "Connection: close\r\n";
		if(@is_array($host['headers']))
		    $http .= implode("\r\n", $host['headers'])."\r\n";
		$http .= "\r\n";
		$http .= $host['post_data'] . "\r\n";
		//echo $http;
		fwrite($s, $http);
		$streams[$i] = array($s, $callback, $host);
	    }
	    else
	    {
		call_user_func($callback, array('response' => array('responseCode'=>'600','responseStatus'=>'Stream socket read timeout'), 'request'=>$host), $i, true); //gateway timed out
	    }
	    //$i++;
	}
    }
    $this->add($streams);
  }

  /* Return response method */
  
  function getresponse()
  {
    if($this->response) return $this->response;
    else return false;
  }
  /* Set connection time-out ms */
  
  function settimeout($time)
  {
    if(is_numeric($time) && $time > 0)
    {
	$this->conn_timeout_ms = $time/1000;
	return $this->conn_timeout_ms;
    }
    else
    {
	return false;
    }
  }

  /* Starting private methods */
  
  private function processStreamEvents($events, $e = false)
  {
  
    if($e) 
    {
	foreach ($events as $fp) {
	    stream_socket_shutdown($fp,STREAM_SHUT_WR);
	    $id = array_search($fp, $this->streams);
	    $e['request'] = $this->listeners[$id][2];
	    call_user_func($this->listeners[$id][1], $e, $id, true);
	    unset($this->streams[$id]);
	}
	//$this->streams = array();
	//$this->listeners = array();
	return;
    }
    foreach ($events as $fp) {
      $id = array_search($fp, $this->streams);
      $this->invokeListener($fp, $id);
      stream_socket_shutdown($fp,STREAM_SHUT_WR); //fclose($fp);
      unset($this->streams[$id]);
    }
  }
  private function invokeListener($fp, $id)
  {
    foreach ($this->listeners as $index => $spec) {
      if ($spec[0] == $fp)
      {
        $data = array();
        $data['response'] = '';
        $data['request'] = $spec[2]; //insert request into return array
    	while (! feof($fp))
    	{
    	    $data['response'] .= fread($fp, 1024);
    	}

        call_user_func($spec[1], $data, $id);
        unset($this->listeners[$index]);
        return ;
      }
    }
  }
  private function addOne($offset, $stream, $listener, $request)
  {
    $this->streams[$offset] = $stream;
    $this->listeners[$offset] = array($stream, $listener, $request);
  }
}


class C8HttpLibException extends RuntimeException {}

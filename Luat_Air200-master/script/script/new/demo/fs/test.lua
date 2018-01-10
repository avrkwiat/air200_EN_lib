module(...,package.seeall)-- All programs are visible


--[[The demo provides four interfaces, the first readfile (filename) read the second writevala (filename, value), write the contents of the file, additional mode,
The third function writevalw (filename, value), write the contents of the file, overwrite mode, the fourth deletefile (filename), delete the file. --]]


--    Function name: readfile (filename)
--Function: Open the file of the input file name, and output the content stored in the inside
--Parameters: file name
--Return Value: None]]
local function readfile(filename)-- Opens the specified file and outputs the content
	
    local filehandle=io.open(filename,"r")-- The first parameter is the file name, the second is open, the 'r' read mode, the 'w' write mode overwrites the data, the 'a' additional mode, the 'b' Form open
	if filehandle then          -- Determine if the file exists
	    local fileval=filehandle:read("*all")-- read out the contents of the file
	  if  fileval  then
	       print(fileval)  -- If the file exists, print the contents of the file
		   filehandle:close()-- close the file
	  else 
	       print("File is empty")--file does not exist
	  end
	else 
	    print("The file does not exist or the file input format is incorrect") -- failed to open 
	end 
	
end





--    Function name: writevala (filename, value)
--Function: Add content to the input file, the content attached to the original file content
--Parameters: The first file name, the second need to add content
--Return Value: None --]]
local function writevala(filename,value)-- In the specified file to add content, function name last one is open mode
	local filehandle = io.open(filename,"a+")-- The first parameter is the file name, the latter is open mode 'r' read mode, 'w' write mode, data is overwritten, 'a' additional mode, 'b' is added behind the mode to open in binary form
	if filehandle then
	    filehandle:write(value)-- Write the content to be written
	    filehandle:close()
	else
	    print("The file does not exist or the file input format is incorrect") -- failed to open 
	end
end





--    Function name: writevalw (filename, value)
--Function: add content to the input file, the newly added content will overwrite the contents of the original file
--Parameters: same as above
--Return Value: None --]]
local function writevalw(filename,value)-- Add content to the specified file
	local filehandle = io.open(filename,"w")-- The first parameter is the file name, the latter is open mode 'r' read mode, 'w' write mode, data is overwritten, 'a' additional mode, 'b' is added behind the mode to open in binary form
	if filehandle then
	    filehandle:write(value)-- Write the content to be written
	    filehandle:close()
	else
	    print("The file does not exist or the file input format is incorrect") -- failed to open 
	end
end



--Function Name: deletefile (filename)
--   Function: delete all the contents of the specified file
--Parameters: file name
--Return Value: None --]]
local function deletefile(filename)-- Delete everything in the specified folder
	local filehandle = io.open(filename,"w")
	if filehandle then
	    filehandle:write()-- Write empty content
	    print("successfully deleted")
		filehandle:close()
	else
	    print("The file does not exist or the file input format is incorrect") -- failed to open 
	end
end



readfile("/3.txt")

writevala("/3.txt","great")

readfile("/3.txt")
writevalw("/3.txt","great")
readfile("/3.txt")

deletefile("/3.txt")
readfile("/3.txt")

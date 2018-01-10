
--Module Name: Math Library Management
--Module function: to achieve common math library functions
--Last modified on: 2017.02.14

module("maths")

--Function name: sqrt
--Function: Find the square root
--Parameters:
--a: Will require the square root of the value, number type
--Return Value: Square root, an integer of type number

function sqrt(a)
	local x
	if a == 0 or a == 1 then return a end
	x=a/2
	for i=1,100 do
		x=(x+a/x)/2
	end
	return x
end

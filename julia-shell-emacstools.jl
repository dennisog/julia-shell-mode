## julia-shell-emacstools.jl --- Helper functions for julia-shell.el
#
# Author: Dennis Ogbe <dogbe@purdue.edu>
#
## Usage:
# This file should not be modified, it is loaded from emacs on the startup of a
# julia shell
#
## TODO:
# -  precompile the module on first load?
#
## License:
#
# Copyright (c) 2015 Dennis Ogbe
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#
# PART 1: The EmacsTools Module
#
###############################################################################

module EmacsTools

export get_completions, get_latex_symbols

# print completions of SUBSTRING
function get_completions(substring::AbstractString)
  c = Base.REPLCompletions.completions(substring, length(substring));
  for completion in c[1]
    println(completion);
  end
end

# print all available LaTeX symbols
function get_latex_symbols()
  c = Base.REPLCompletions.latex_symbols;
  for (latex, unicode) in sort!(collect(c), by=x->x[2])
    println("$latex $unicode")
  end
end

end # module

#
# PART 2: Load the EmacsTools module and do other customizations
#
###############################################################################

import EmacsTools

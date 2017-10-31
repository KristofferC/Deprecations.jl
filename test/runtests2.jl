

using Deprecations
using Deprecations: overlay_parse, apply_formatter, changed_text
using Base.Test
using TestSetExtensions
@testset TestSetExtensions "foo" begin
edit_text(raw"""
"ABC$T"
if cset == HDF5.H5T_CSET_ASCII
    return Compat.ASCIIString
elseif cset == HDF5.H5T_CSET_UTF8
    return Compat.UTF8String
end
""")[2] == raw"""
"ABC$T"
if cset == HDF5.H5T_CSET_ASCII
    return String
elseif cset == HDF5.H5T_CSET_UTF8
    return String
end
"""
end

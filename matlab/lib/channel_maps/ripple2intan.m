function intan_order = ripple2intan(ripple)

if size(ripple,1) > 1
    ripple = ripple';
end
% Find Intan mapping for arbitrary ordering of Ripple channels

% Let Ripple order be 1-32
intan_order = 1:32; 
% Mapping from Ripple to Intan is invariant with respect to electrode to
% Ripple channel map
ripple_order = [15	16	14	17	13	18	12	19	11	20	10	21	9	22	8	23	7	24	6	25	5	26	4	27	3	28	2	29	1	30	0	31];

N = numel(ripple);
% Reorder Intan channels with position indices
p = zeros(1,N);
for i = 1:N
    p(i) = find(intan_order == ripple(i));
end
% Check indices transform original to new
assert(isequal(intan_order(p), ripple));

% Transform ripple_order with p indices
intan_order = ripple_order(p)';
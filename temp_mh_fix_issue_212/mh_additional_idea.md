MH notes to future self:

Obvious next step is to see in Vice how the startup actually should look.

Then stick to the very same cart version for example the "1.1 fix" version and take it from there.

We could also use a debug output dump of the startup sequence of Vice, I know it can output interesting logs (todo: how), where we see each cycle. With these logs we could ask Claude to simulate "in its head", if what we programmed in VHDL would actually support this.

So first we would need this instrumented Vice mode to see a groud truth and then try how far we come without needing to instrument Vivado.

But if we need to do that, I do remember that MJoergen generated some code for outputting infos (executed commands + registers etc?) via serial. This might be super valuable and speed up the process greatly, because the alternative via ILA is super slow. So with MJoergen I might want to discuss: Can we enhance M2M to generate a debug out similar to the Vice debug out that supports coding with AIs. And then this debug out could be fed into AIs together with Vice ground truth.

M2M enhancement: AI debugging support features.
